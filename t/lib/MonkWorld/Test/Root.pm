package MonkWorld::Test::Root;

use v5.40;
use Test::Class::Most;
use Test::Mojo;
use HTTP::Status qw(HTTP_OK);

INIT { Test::Class->runtests }

sub index_has_links : Test(6) ($self) {
    my $t = Test::Mojo->new('MonkWorld::API');

    my $version = $MonkWorld::API::VERSION;
    my $test = $t->get_ok('/')
        ->header_is('Content-Type' => "application/vnd.monkworld+json;version=$version")
        ->status_is(HTTP_OK);

    $test->json_is('/_links/self' => {
        href => '/',
    });

    $test->json_is('/_links/create_node_type' => {
        href => '/node-type',
        method => 'POST',
        headers => { Authorization => 'Bearer %s' },
        json => {
            name => 'NODE_TYPE_NAME',
            id => 'NODE_TYPE_ID',
        },
    });

    $test->json_is('/_links/create_monk' => {
         href => '/monk',
         method => 'POST',
         headers => { Authorization => 'Bearer %s' },
         json => {
             username => 'MONK_USERNAME',
             id => 'MONK_ID',
         },
     });
}