package MonkWorld::Test::NodeType;

use v5.40;
use HTTP::Status qw(HTTP_CREATED HTTP_OK);
use Mojo::Pg;
use Mojo::URL;
use Test::Mojo;
use MonkWorld::API::Constants qw(NODE_TYPE_PERLQUESTION NODE_TYPE_NOTE);
use MonkWorld::API::Request;

use Test::Class::Most
  parent => 'MonkWorld::Test::Base';

sub schema { 'node_type_test' }

sub db_teardown : Test(teardown) ($self) {
    $self->pg->db->delete('node_type', { id => { -not_in => [NODE_TYPE_PERLQUESTION, NODE_TYPE_NOTE] } });
}

sub a_node_type_can_be_created : Test(2) ($self) {
    my $t = $self->mojo;

    $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    subtest 'without an ID' => sub {
        my $sitemap = $t->get_ok('/')->tx->res->json;

        my $req = MonkWorld::API::Request
            ->new(link_meta => $sitemap->{_links}{create_node_type})
            ->replace_json_val(NODE_TYPE_NAME => 'a_node_type')
            ->ignore_json_kv('id');

        my $tx = $t->ua->build_tx($req->method => $req->href => $req->headers => json => $req->json);

        $t->request_ok($tx)
        ->status_is(HTTP_CREATED)
        ->header_like('Location' => qr{/node-type/\d+$})
        ->json_is('/name' => 'a_node_type')
        ->json_has('/id');
    };

    subtest 'with an explicit ID' => sub {
        my $id = $t->tx->res->json->{id};
        ok $id > 0, 'ID is a positive integer';
        my $explicit_id = $id + 2;

        my $sitemap = $t->get_ok('/')->tx->res->json;
        my $req = MonkWorld::API::Request
            ->new(link_meta => $sitemap->{_links}{create_node_type})
            ->replace_json_val(NODE_TYPE_NAME => 'another_node_type')
            ->replace_json_val(NODE_TYPE_ID => $explicit_id)
        ;

        my $tx = $t->ua->build_tx($req->tx_args);

        $t->request_ok($tx)
        ->status_is(HTTP_CREATED)
        ->header_like('Location' => qr{/node-type/\d+$})
        ->json_is('/id' => $explicit_id)
        ->json_is('/name' => 'another_node_type');
    };
}

sub a_node_type_cannot_be_created_if_name_exists : Test(6) ($self) {
    my $node_type_name = 'test_node_type';

    my $t = $self->mojo;
    my $sitemap = $t->get_ok('/')->tx->res->json;

    # First, create a node type
    my $req = MonkWorld::API::Request
        ->new(link_meta => $sitemap->{_links}{create_node_type})
        ->replace_json_val(NODE_TYPE_NAME => $node_type_name)
        ->ignore_json_kv('id');

    my $tx1 = $t->ua->build_tx($req->tx_args);

    $t->request_ok($tx1)
      ->status_is(HTTP_CREATED);

    # Then try to create another node type with the same name
    # Mystery: trying to reuse the tx doesn't work
    my $tx2 = $t->ua->build_tx($req->tx_args);

    $t->request_ok($tx2)
      ->status_is(HTTP::Status::HTTP_CONFLICT)
      ->json_like('/error' => qr/already exists/);
}

sub the_collection_of_all_node_types_can_be_retrieved : Test(4) ($self) {
    # create some node types
    foreach my $n (1 .. 2) {
        my $section = "Section_$n";
        $self->{$section} = $self->pg->db->insert(
            'node_type',
            { name => $section, id => $n },
            { returning => [ qw(id name) ] }
        )->hash;
    }

    my $t = $self->mojo;
    my $sitemap = $t->get_ok('/')->tx->res->json;

    # First, create a node type
    my $req = MonkWorld::API::Request
        ->new(link_meta => $sitemap->{_links}{get_all_sections})
        ;

    my $tx = $t->ua->build_tx($req->tx_args);

    $t->request_ok($tx)
      ->status_is(HTTP_OK);
    my $result = $t->tx->res->json;

    my $expected_json = {
        _links => {
            self => {
                href => '/sections'
            }
        },
        node_types => [
            {
                id   => 1,
                name => 'Section_1'
            },
            {
                id   => 2,
                name => 'Section_2'
            }
        ]
    };
    eq_or_diff $result, $expected_json;
}
