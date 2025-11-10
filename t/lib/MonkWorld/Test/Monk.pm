package MonkWorld::Test::Monk;

use v5.40;
use HTTP::Status qw(HTTP_CREATED HTTP_UNPROCESSABLE_CONTENT);
use Mojo::Pg;
use Mojo::URL;
use Test::Mojo;
use MonkWorld::API::Request;

use Test::Class::Most
  parent => 'MonkWorld::Test::Base';

sub schema { 'monk_test' }

sub db_teardown : Test(teardown) ($self) {
    $self->pg->db->delete('monk', { id => { -not_in => [$self->anonymous_user_id] } });
}

sub a_monk_can_be_created : Test(2) ($self) {
    my $t = $self->mojo;

    $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    subtest 'without an ID' => sub {
        my $sitemap = $t->get_ok('/')->tx->res->json;

        my $req = MonkWorld::API::Request
            ->new(link_meta => $sitemap->{_links}{create_monk})
            ->replace_json_val(MONK_USERNAME => 'testuser1')
            ->ignore_json_kv('id');

        my $tx = $t->ua->build_tx($req->tx_args);

        $t->request_ok($tx)
          ->status_is(HTTP_CREATED)
          ->header_like('Location' => qr{/monk/\d+$})
          ->json_is('/username' => 'testuser1')
          ->json_has('/id');
    };

    subtest 'with an explicit ID' => sub {
        my $id = $t->tx->res->json->{id};
        ok $id > 0, 'ID is a positive integer';
        my $explicit_id = $id + 1;

        my $sitemap = $t->get_ok('/')->tx->res->json;
        my $req = MonkWorld::API::Request
            ->new(link_meta => $sitemap->{_links}{create_monk})
            ->replace_json_val(MONK_USERNAME => 'testuser2')
            ->replace_json_val(MONK_ID => $explicit_id);

        my $tx = $t->ua->build_tx($req->tx_args);

        $t->request_ok($tx)
          ->status_is(HTTP_CREATED)
          ->header_like('Location' => qr{/monk/$explicit_id$})
          ->json_is('/id' => $explicit_id)
          ->json_is('/username' => 'testuser2');
    };
}

sub a_monk_cannot_be_created_without_a_username : Tests(4) ($self) {
    my $t = $self->mojo;

    $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    my $sitemap = $t->get_ok('/')->tx->res->json;

    my $req = MonkWorld::API::Request
        ->new(link_meta => $sitemap->{_links}{create_monk})
        ->ignore_json_kv('id')
        ->ignore_json_kv('username')
    ;

    my $tx = $t->ua->build_tx($req->tx_args);

    $t->request_ok($tx)
      ->status_is(HTTP_UNPROCESSABLE_CONTENT)
      ->json_like('/error' => qr/username is required/);
}

sub a_monk_cannot_be_created_with_an_invalid_id : Tests(5) ($self) {
    my $t = $self->mojo;

    $ENV{MONKWORLD_AUTH_TOKEN}
        or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    my $sitemap = $t->get_ok('/')->tx->res->json;

    my $req = MonkWorld::API::Request
        ->new(link_meta => $sitemap->{_links}{create_monk})
        ->replace_json_val(MONK_USERNAME => 'testuser')
        ->replace_json_val(MONK_ID => 'invalid_id');

    my $tx = $t->ua->build_tx($req->tx_args);

    $t->request_ok($tx)
      ->status_is(HTTP_UNPROCESSABLE_CONTENT)
      ->json_has('/error')
      ->json_like('/error' => qr/must be a positive integer/);
}

sub a_monk_cannot_be_created_if_username_exists : Tests(7) ($self) {
    my $t = $self->mojo;

    $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    my $sitemap = $t->get_ok('/')->tx->res->json;

    # First, create a monk
    my $req = MonkWorld::API::Request
        ->new(link_meta => $sitemap->{_links}{create_monk})
        ->replace_json_val(MONK_USERNAME => 'test_user')
        ->ignore_json_kv('id');

    my $tx1 = $t->ua->build_tx($req->tx_args);
    $t->request_ok($tx1)->status_is(HTTP_CREATED);

    # Then try to create another monk with the same username
    # Mystery: trying to reuse the tx doesn't work

    my $tx2 = $t->ua->build_tx($req->tx_args);
    $t->request_ok($tx2)
      ->status_is(HTTP::Status::HTTP_CONFLICT)
      ->json_has('/error')
      ->json_like('/error' => qr/Username already exists/);
}