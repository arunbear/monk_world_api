package MonkWorld::Test::NodeType;

use v5.40;
use HTTP::Status qw(HTTP_CREATED);
use Mojo::Pg;
use Mojo::URL;
use Test::Mojo;
use MonkWorld::API::Constants qw(NODE_TYPE_PERLQUESTION NODE_TYPE_NOTE);

use Test::Class::Most
  parent => 'MonkWorld::Test::Base';

sub schema { 'node_type_test' }

sub db_teardown : Test(teardown) ($self) {
    $self->pg->db->delete('node_type', { id => { -not_in => [NODE_TYPE_PERLQUESTION, NODE_TYPE_NOTE] } });
}

sub a_node_type_can_be_created : Test(2) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    subtest 'without an ID' => sub {
        $t->post_ok(
            '/node-type' => {
                'Authorization' => "Bearer $auth_token"
            } => json => {
                name => 'a_node_type'
            }
        )
        ->status_is(HTTP_CREATED)
        ->header_like('Location' => qr{/node-type/\d+$})
        ->json_is('/name' => 'a_node_type')
        ->json_has('/id');
    };

    subtest 'with an explicit ID' => sub {
        my $id = $t->tx->res->json->{id};
        ok $id > 0, 'ID is a positive integer';
        my $explicit_id = $id + 1;
        $t->post_ok(
            '/node-type' => {
                'Authorization' => "Bearer $auth_token"
            } => json => {
                id   => $explicit_id,
                name => 'another_node_type'
            }
        )
        ->status_is(HTTP_CREATED)
        ->header_like('Location' => qr{/node-type/\d+$})
        ->json_is('/id' => $explicit_id)
        ->json_is('/name' => 'another_node_type');
    };
}

sub a_node_type_cannot_be_created_if_name_exists : Test(5) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
        or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    my $node_type_name = 'test_node_type';

    # First, create a node type
    $t->post_ok(
        '/node-type' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            name => $node_type_name
        }
    )->status_is(HTTP_CREATED);

    # Then try to create another node type with the same name
    $t->post_ok(
        '/node-type' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            name => $node_type_name
        }
    )
    ->status_is(HTTP::Status::HTTP_CONFLICT)
    ->json_like('/error' => qr/already exists/);
}
