package MonkWorld::Test::Monk;

use v5.40;
use HTTP::Status qw(HTTP_CREATED HTTP_UNPROCESSABLE_CONTENT);
use Mojo::Pg;
use Mojo::URL;
use Test::Mojo;

use Test::Class::Most
  parent => 'MonkWorld::Test::Base';

sub schema { 'monk_test' }

sub db_teardown : Test(teardown) ($self) {
    $self->pg->db->delete('monk', { id => { -not_in => [$self->anonymous_user_id] } });
}

sub a_monk_can_be_created : Test(2) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
        or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    subtest 'without an ID' => sub {
        $t->post_ok(
            '/monk' => {
                'Authorization' => "Bearer $auth_token"
            } => json => {
                username => 'testuser1'
            }
        )
        ->status_is(HTTP_CREATED)
        ->header_like('Location' => qr{/monk/\d+$})
        ->json_is('/username' => 'testuser1')
        ->json_has('/id');
    };

    subtest 'with an explicit ID' => sub {
        my $id = $t->tx->res->json->{id};
        ok $id > 0, 'ID is a positive integer';
        my $explicit_id = $id + 1;
        $t->post_ok(
            '/monk' => {
                'Authorization' => "Bearer $auth_token"
            } => json => {
                id => $explicit_id,
                username => 'testuser2'
            }
        )
        ->status_is(HTTP_CREATED)
        ->header_like('Location' => qr{/monk/$explicit_id$})
        ->json_is('/id' => $explicit_id)
        ->json_is('/username' => 'testuser2');
    };
}

sub a_monk_cannot_be_created_without_a_username : Tests(3) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    $t->post_ok(
        '/monk' => {
            'Authorization' => "Bearer $auth_token"
        } => json => { }
    )
    ->status_is(HTTP_UNPROCESSABLE_CONTENT)
    ->json_like('/error' => qr/username is required/);
}

sub a_monk_cannot_be_created_with_an_invalid_id : Tests(4) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
        or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    $t->post_ok(
        '/monk' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            username => 'testuser',
            id => 'invalid_id'
        }
    )
    ->status_is(HTTP_UNPROCESSABLE_CONTENT)
    ->json_has('/error')
    ->json_like('/error' => qr/must be a positive integer/);
}

sub a_monk_cannot_be_created_if_username_exists : Tests(6) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
        or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    my $a_username = 'a_user';

    # First, create a monk
    $t->post_ok(
        '/monk' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            username => $a_username
        }
    )->status_is(HTTP_CREATED);

    # Then try to create another monk with the same username
    $t->post_ok(
        '/monk' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            username => $a_username
        }
    )
    ->status_is(HTTP::Status::HTTP_CONFLICT)
    ->json_has('/error')
    ->json_like('/error' => qr/Username already exists/);
}