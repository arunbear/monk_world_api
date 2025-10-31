package MonkWorld::API::Model::Node;

use v5.40;
use Devel::Assert 'on';
use Mojo::Base -base, -signatures;
use MonkWorld::API::Constants 'NODE_TYPE_NOTE';

has 'pg';

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
    my $result = $db->insert('node', {
        $node_data->{node_id} ? (id => $node_data->{node_id}) : (),
        $node_data->{created} ? (created_at => $node_data->{created}) : (),
        node_type_id => $node_data->{node_type_id},
        author_id    => $node_data->{author_id},
        title        => $node_data->{title},
        doctext      => $node_data->{doctext},
    }, {
        returning => ['id', 'node_type_id', 'author_id', 'title', 'doctext', 'created_at'],
        on_conflict => undef,
    });

    my $collection = $result->hashes;
    if ($collection->size > 0) {
        if ($node_data->{node_id}) {
            # Inserting with an explicit id can desynchronize the auto increment sequence
            # So, sync the sequence to prevent future ID conflicts
            # https://dba.stackexchange.com/a/210599
            $db->query("SELECT setval(pg_get_serial_sequence('node', 'id'), COALESCE((SELECT MAX(id) FROM node), 0), true)");
        }
        else {
            my $inserted = $collection->first;
            $node_data->{node_id} //= $inserted->{id};
        }
    }

    if ($node_data->{node_type_id} == NODE_TYPE_NOTE) {
        my $path = $self->_create_note($db, $node_data);

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

    my @path_info = ($node_data->{node_id});
    if ($parent_node eq $root_node) {
        unshift @path_info, $parent_node;
    }
    else  {
        # Get parent's path and append current node ID
        my $parent = $db->select('note', ['path'], { node_id => $parent_node })->hash;
        if (!defined $parent) {
            die "Non root parent $parent_node not present for node $node_data->{node_id}";
        }
        unshift @path_info, $parent->{path};
    }
    my $path = join('.', @path_info);

    my $note_results = $db->insert('note', {
        node_id     => $node_data->{node_id},
        root_node   => $root_node,
        parent_node => $parent_node,
        path        => $path
    }, { on_conflict => undef });

    printf("Rows inserted into note: %d\n", $note_results->rows);
    return $path;
}