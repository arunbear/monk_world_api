package MonkWorld::API::Model::NodeType;

use v5.40;
use Mojo::Base 'MonkWorld::API::Model::Base', -signatures;

sub table_name ($self) { 'node_type' }

sub create ($self, $node_type_data) {
    my $db = $self->pg->db;

    my $result = $db->insert(
        $self->table_name,
        $node_type_data,
        {
            returning => ['id', 'name'],
            on_conflict => undef,
        }
    );
    my $collection = $result->hashes;
    if ($collection->is_not_empty && $node_type_data->{id}) {
        $self->sync_id_sequence($db);
    }
    return $collection;
}

sub get_all ($self) {
    my $db = $self->pg->db;
    my $result = $db->select(
        $self->table_name,
        ['id', 'name'],
        {},
        { order_by => 'name' }
    );
    return $result->hashes->to_array;
}