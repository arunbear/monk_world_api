package MonkWorld::API::Model::Monk;

use v5.40;
use Mojo::Base 'MonkWorld::API::Model::Base', -signatures;

sub table_name ($self) { 'monk' }

sub create ($self, $monk_data) {
    my $db = $self->pg->db;

    my $result = $db->insert(
        $self->table_name,
        $monk_data,
        {
            returning => ['id', 'username', 'is_anonymous', 'created_at'],
            on_conflict => undef,
        }
    );
    my $collection = $result->hashes;
    if ($collection->is_not_empty && $monk_data->{id}) {
        $self->sync_id_sequence($db);
    }
    return $collection;
}