package MonkWorld::API::Model::Node;

use v5.40;
use Devel::Assert 'on';
use Mojo::Base 'MonkWorld::API::Model::Base', -signatures;
use MonkWorld::API::Constants 'NODE_TYPE_NOTE';

sub table_name ($self) { 'node' }

sub get_thread ($self, $node_id) {
    my $rows = $self->_fetch_thread_rows($node_id);
    return {} unless @$rows;

    my $result = {};
    my @wanted_fields = qw(title created_at author_username author_id);

    for my $row (@$rows) {
        my $is_top = $row->{id} == $node_id;

        if ($is_top) {
            my @context_fields = qw(section_name);
            if ($node_id != $row->{root_id}) {
                push @context_fields, qw(root_id root_title parent_id parent_title);
            }
            $result->{$row->{id}} = {
                map { $_ => $row->{$_} } (@wanted_fields, @context_fields)
            };
            next;
        }

        # Handle replies by walking the path
        my @ids =
            grep { $_ >= $node_id } # for replies we don't want ancestors
            split /\./, $row->{path};

        # Start from the top
        my $cursor = $result->{$ids[0]} ||= {};

        # Walk the path to find the right place for this node
        for my $seg_id (@ids[1..$#ids]) {
            $cursor->{reply}{$seg_id} //= {};
            $cursor = $cursor->{reply}{$seg_id};
        }

        # Set the node's fields
        $cursor->{$_} = $row->{$_} for @wanted_fields;
    }

    return $result;
}

sub create ($self, $node_data) {
    my $db = $self->pg->db;
    try {
        my $tx = $db->begin;
        my $collection = $self->_create($db, $node_data);
        $tx->commit;
        return $collection;
    } catch ($error) {
        my $reason = $error;
        if ($error =~ /(Key .+ is not present in table "node")/s) {
            $reason = $1;
        }
        die "Failed to create node $node_data->{node_id}: $reason";
    }
}

sub _create ($self, $db, $node_data) {
    my $result = $db->insert($self->table_name, {
        $node_data->{node_id} ? (id => $node_data->{node_id}) : (),
        $node_data->{created} ? (created_at => $node_data->{created}) : (),
        node_type_id => $node_data->{node_type_id},
        author_id    => $node_data->{author_id},
        title        => $node_data->{title},
        doctext      => $node_data->{doctext},
    }, {
        returning => [qw(id node_type_id author_id title doctext created_at path)],
        on_conflict => undef,
    });

    my $collection = $result->hashes;
    if ($collection->is_not_empty) {
        if ($node_data->{node_id}) {
            $self->sync_id_sequence($db);
        }
        else {
            my $inserted = $collection->first;
            $node_data->{node_id} //= $inserted->{id};
        }
    }
    else {
        # this was an insert with id (importer)
        assert $node_data->{node_id};
    }

    if ($node_data->{node_type_id} == NODE_TYPE_NOTE) {
        $self->_create_note($db, $node_data);
        my $path = $self->_create_note_path($db, $node_data);

        $collection->each(sub ($e, $i) {
            $e->{path} = $path;
            $e->{parent_node} = $node_data->{parent_node};
            $e->{root_node}   = $node_data->{root_node};
        });
    }

    return $collection;
}

sub _create_note ($self, $db, $node_data) {
    my $root_node   = $node_data->{root_node};
    my $parent_node = $node_data->{parent_node};

    my $note_results = $db->insert('note', {
        node_id     => $node_data->{node_id},
        root_node   => $root_node,
        parent_node => $parent_node,
        # path        => $path
    }, { on_conflict => undef });

    $self->log->debug(sprintf "Rows inserted into note: %d", $note_results->rows);
}

sub _create_note_path ($self, $db, $node_data) {
    my $parent_node = $node_data->{parent_node};
    my $parent = $db->select($self->table_name, ['path'], { id => $parent_node })->hash;

    my $note_path = "$parent->{path}.$node_data->{node_id}";
    my $set = my $where = '';
    my $results = $db->update(
        $self->table_name,
        { $set . path => $note_path },
        { $where . id => $node_data->{node_id} },
        { returning => 'path' },
    );
    return $results->hash->{path};
}

sub _fetch_thread_rows ($self, $node_id) {
    my $db = $self->pg->db;

    my $rows = $db->query(q{
          SELECT
            n.id,
            n.title,
            n.path,
            n.created_at,
            m.username AS author_username,
            m.id AS author_id,
            r.id AS root_id,
            r.title AS root_title,
            p.id AS parent_id,
            p.title AS parent_title,
            s.name AS section_name
          FROM node n
          JOIN monk m ON m.id = n.author_id
          JOIN node r ON r.id = (subpath(n.path, 0, 1))::text::bigint
          JOIN node_type s ON s.id = r.node_type_id
          LEFT JOIN node p ON p.path = subpath(n.path, 0, -1)
          WHERE n.path <@ (SELECT path FROM node WHERE id = $1)
            OR n.id = $1
          ORDER BY n.id ASC
        }, $node_id
    )->hashes->to_array;

    return $rows;
}
