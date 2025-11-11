package MonkWorld::Test::Node;

use v5.40;
use HTTP::Status qw(HTTP_CREATED HTTP_CONFLICT);

use Test::Class::Most
  parent => 'MonkWorld::Test::Base';

sub schema { 'node_test' }

sub a_node_can_be_created : Test(4) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    # First, create the node dependencies
    my $node_type = $self->create_node_type('post');
    my $node_type_id = $node_type->{id};
    my $anon_user_id = $self->anonymous_user_id;

    subtest 'without an ID' => sub {
        my $sitemap = $self->get_sitemap;
        my $req = MonkWorld::API::Request
            ->new(link_meta => $sitemap->{_links}{create_node})
            ->update_json_entries(
                node_type_id => $node_type_id,
                author_id    => $anon_user_id,
                title        => 'Test Node',
                doctext      => 'This is a test node',
            )
            ->ignore_json_kv('node_id')
        ;
        my $tx = $t->ua->build_tx($req->tx_args);

        $t->request_ok($tx)
        ->status_is(HTTP_CREATED)
        ->header_like('Location' => qr{/node/\d+$})
        ->json_has('/id')
        ->json_has('/created_at')
        ->json_is('/title' => 'Test Node')
        ->json_is('/doctext' => 'This is a test node')
        ->json_is('/node_type_id' => $node_type_id);
    };

    subtest 'with an explicit ID' => sub {
        my $id = $t->tx->res->json->{id};
        ok $id > 0, 'ID is a positive integer';
        my $explicit_id = $id + 2; # better than 1 as auto increment would give a false pass

        my $sitemap = $self->get_sitemap;
        my $req = MonkWorld::API::Request
            ->new(link_meta => $sitemap->{_links}{create_node})
            ->update_json_entries(
                node_id      => $explicit_id,
                node_type_id => $node_type_id,
                author_id    => $anon_user_id,
                title        => 'Node With ID',
                doctext      => 'This node has an explicit ID'
            );
        my $tx = $t->ua->build_tx($req->tx_args);

        $t->request_ok($tx)
        ->status_is(HTTP_CREATED)
        ->header_like('Location' => qr{/node/\d+$})
        ->json_is('/id' => $explicit_id)
        ->json_is('/title' => 'Node With ID')
        ->json_is('/doctext' => 'This node has an explicit ID')
        ->json_is('/node_type_id' => $node_type_id);
    };
}

sub a_node_cannot_be_created_if_id_already_exists : Test(8) ($self) {
    my $t = $self->mojo;

    $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    # First, create the node type
    my $node_type = $self->create_node_type('article');
    my $node_type_id = $node_type->{id};
    my $anon_user_id = $self->anonymous_user_id;
    my $node_id = 1001;  # Explicit ID for testing

    # Get the sitemap to access the create_node link
    my $sitemap = $self->get_sitemap;

    # Create first node with explicit ID using HAL links
    {
        my $req = MonkWorld::API::Request
            ->new(link_meta => $sitemap->{_links}{create_node})
            ->update_json_entries(
                node_id      => $node_id,
                node_type_id => $node_type_id,
                author_id    => $anon_user_id,
                title        => 'First Node',
                doctext      => 'This is the first node'
            );
        my $tx = $t->ua->build_tx($req->tx_args);

        $t->request_ok($tx)
            ->status_is(HTTP_CREATED);
    }

    # Try to create another node with the same ID using HAL links
    {
        my $req = MonkWorld::API::Request
            ->new(link_meta => $sitemap->{_links}{create_node})
            ->update_json_entries(
                node_id      => $node_id,  # Same ID as above
                node_type_id => $node_type_id,
                author_id    => $anon_user_id,
                title        => 'Duplicate Node',
                doctext      => 'This should fail'
            );
        my $tx = $t->ua->build_tx($req->tx_args);

        $t->request_ok($tx)
            ->status_is(HTTP::Status::HTTP_CONFLICT)
            ->json_like('/error' => qr/already exists/);
    }
}