package MonkWorld::API::Model::Base;

use v5.40;
use Mojo::Base -base, -signatures;

has 'log';
has 'pg';

sub table_name ($self) { ... }

=head2 sync_id_sequence($db)

Synchronizes the id sequence with the current max ID.

This prevents ID conflicts when inserting with explicit IDs.

See: https://dba.stackexchange.com/a/210599

=cut

sub sync_id_sequence ($self, $db) {
    my $table_name = $self->table_name;
    $db->query("SELECT setval(pg_get_serial_sequence('$table_name', 'id'), COALESCE(MAX(id), 0) + 1) FROM $table_name");
}