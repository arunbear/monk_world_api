package MonkWorld::Test::Root;

use v5.40;
use HTTP::Status qw(HTTP_OK);
use Test::Mojo;

use Test::Class::Most
  parent => 'MonkWorld::Test::Base';

sub schema { 'root_test' }

sub index_has_links : Test(11) ($self) {
    my $t = $self->mojo;

    my $version = $MonkWorld::API::VERSION =~ tr/_//dr;
    $t->get_ok('/')
        ->header_is('Content-Type' => "application/vnd.monkworld+json;version=$version")
        ->status_is(HTTP_OK)
        ->json_has('/_links/self/href')
        ->json_is('/_links/self/href' => '/')

        ->json_has('/_links/create_node_type/href')
        ->json_is('/_links/create_node_type/href' => '/node-type')
        ->json_is('/_links/create_node_type/method' => 'POST')
        ->json_is('/_links/create_node_type/headers/Authorization' => 'Bearer %s')
        ->json_is('/_links/create_node_type/json/name' => 'NODE_TYPE_NAME')
        ->json_is('/_links/create_node_type/json/id' => 'NODE_TYPE_ID')
    ;
}