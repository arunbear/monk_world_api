package MonkWorld::API::Model::Threads;

use v5.40;
use Mojo::Base 'MonkWorld::API::Model::Base', -signatures;

sub get_threads ($self, $cutoff_interval = '1 day') {
    my $rows = $self->fetch_threads_rows($cutoff_interval);

    my $result = {};

    for my $row (@$rows) {
        my $section_key = $row->{section_name};

        my $is_root_node = !defined $row->{parent_node};
        if ($is_root_node) {
            $result->{$section_key}{ $row->{id} }{title} = $row->{title};
            next;
        }

        # This is a reply.
        # Place it in a nested hash by walking its path segments.
        # Example:
        #   Root thread id 200; first reply 201; reply to that 202.
        #   note.path for node 202 is "200.201.202".
        #   We split to [200, 201, 202], take root_id=200, then create
        #   reply{201} and reply{202} under result->{Section}{200}.
        my @ids = split m{\.}, ($row->{path} // '');
        next unless @ids;

        my $root_id = shift @ids;
        my $cursor = $result->{$section_key}{$root_id};

        for my $seg_id (@ids) {
            $cursor->{reply}{$seg_id} //= {};
            $cursor = $cursor->{reply}{$seg_id};
        }
        $cursor->{title} //= $row->{title};
    }

    return $result;
}

sub fetch_threads_rows ($self, $cutoff_interval = '1 day') {
    my $db = $self->pg->db;

    # Query notes:
    # It returns threads that have been entirely created in the $cutoff_interval,
    # OR any replies created in the $cutoff_interval, plus their ancestors.
    #
    # Why JOIN node r ON r.id = COALESCE(no.root_node, n.id)?
    # - For replies, note.root_node points to the thread's root node.
    # - For root posts, there is no note row, so COALESCE falls back to n.id.
    # This gives us a canonical root id (r.id) for every row, which we use to:
    #   * derive the section from the root node's node_type (JOIN node_type s ON s.id = r.node_type_id)
    #   * evaluate the cutoff at the thread level via EXISTS (...) WHERE no2.root_node = r.id
    my $rows = $db->query(q{
          WITH recent AS (
            SELECT id, path
            FROM node
            WHERE created_at >= now() - $1::interval
          )
          SELECT
            n.id,
            n.title,
            n.path,
            s.name AS section_name,
            no.parent_node
          FROM node n
          LEFT JOIN note no ON no.node_id = n.id
          JOIN node r ON r.id = COALESCE(no.root_node, n.id)
          JOIN node_type s ON s.id = r.node_type_id
          JOIN recent rc ON n.path @> rc.path
          ORDER BY n.id ASC
        }, $cutoff_interval
    )->hashes->to_array;

    return $rows;
}

__DATA__