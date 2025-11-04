package MonkWorld::Test::Request;

use v5.40;
use Test::Class::Most;
use MonkWorld::API::Request;

INIT { Test::Class->runtests }

sub setup : Test(setup) {
    $ENV{MONKWORLD_AUTH_TOKEN} = 'test_token_123';
}

sub when_creating_a_request : Test(4) ($self) {
    my %req_args = (link_meta => {
        method  => 'POST',
        href    => '/resource',
        headers => {
            'Authorization' => 'Bearer %s',
        },
        json => {
            id => 1,
        },
    });
    note 'With args:'; explain \%req_args;
    my $req = MonkWorld::API::Request->new(%req_args);

    is $req->method => 'POST', 'it has an HTTP method';
    is $req->href => '/resource', 'it has a URI';

    my $headers = $req->headers;
    is_deeply $headers => { 'Authorization' => 'Bearer test_token_123' }, 'it has an Auth header';

    my $json = $req->json;
    is_deeply $json => { id => 1 }, 'it has a JSON payload';
}

sub auth_tokens_are_optional : Test(1) ($self) {
    my %req_args = (
        link_meta => {
            method  => 'POST',
            href    => '/resource',
            headers => { },
        },
        with_auth_token => false,
    );
    note 'This request:'; explain \%req_args;
    my $req = MonkWorld::API::Request->new(%req_args);
    is_deeply $req->headers => {}, 'does not have an auth token header';
}

sub invalid_bearer_tokens_are_rejected : Test(1) ($self) {
    $ENV{MONKWORLD_AUTH_TOKEN} = 'INVALID TOKEN WITH SPACES';

    throws_ok {
        MonkWorld::API::Request->new(link_meta => {
            method  => 'GET',
            href    => '/api/resource',
            headers => {
                'Authorization' => 'Bearer %s',
            },
        });
    } qr/did not pass type constraint/;
}

sub json_placeholder_values_can_be_replaced : Test(1) ($self) {
    my %req_args = (link_meta => {
        method  => 'POST',
        href    => '/resource',
        json => {
            enabled => 'ENABLED',
        },
    }, with_auth_token => false);
    note 'The placeholder value in this request:'; explain \%req_args;
    my $req = MonkWorld::API::Request->new(%req_args);

    $req->replace_json_val('ENABLED', 'false');
    is $req->json->{enabled} => 'false', 'is replaced';
}

sub non_existent_placeholder_values_are_ignored : Test(1) ($self) {
    my %req_args = (link_meta => {
        method  => 'POST',
        href    => '/resource',
        json => {
            id      => 1,
            enabled => 'ENABLED',
        },
    }, with_auth_token => false);

    note 'The JSON in this request:'; explain \%req_args;
    my $req = MonkWorld::API::Request->new(%req_args);

    my $before_json = { $req->json->%* };
    $req->replace_json_val('NON-EXISTENT', 'new-value');
    is_deeply($req->json, $before_json, 'is unchanged');
}

sub removing_an_existing_key_from_json_removes_that_entry : Test(1) ($self) {
    my %req_args = (link_meta => {
        method  => 'POST',
        href    => '/resource',
        headers => {},
        json    => { id => 1, name => 'Test' },
    }, with_auth_token => false);

    note "The 'name' JSON entry in this request:"; explain \%req_args;
    my $req = MonkWorld::API::Request->new(%req_args);

    $req->ignore_json_kv('name');
    is_deeply $req->json => { id => 1 }, 'is removed';
}

sub removing_a_non_existent_key_leaves_json_unchanged : Test(1) ($self) {
    my %req_args = (link_meta => {
        method  => 'POST',
        href    => '/resource',
        headers => {},
        json    => { id => 1 },
    });

    note 'The JSON in this request:'; explain \%req_args;
    my $req = MonkWorld::API::Request->new(%req_args);

    my $before_json = { %{$req->json} };
    $req->ignore_json_kv('NON-EXISTENT-KEY');
    is_deeply($req->json, $before_json, 'is unchanged');
}

sub can_generate_args_for_mojo_build_tx : Test(1) ($self) {
    my $req = MonkWorld::API::Request->new(link_meta => {
        method  => 'POST',
        href    => '/resource',
        headers => {
            'Authorization' => 'Bearer %s',
        },
        json => {
            id => 1,
        },
    });

    my @args = $req->tx_args;

    my $expected = [
        'POST',
        '/resource',
        {
            'Authorization' => 'Bearer test_token_123',
        },
        'json',
        {
            id => 1,
        },
    ];
    eq_or_diff \@args, $expected;
}

sub invalid_http_methods_are_rejected : Test(1) ($self) {
    throws_ok {
        MonkWorld::API::Request->new(
            link_meta => {
                method  => 'INVALID_METHOD',
                href    => '/resource',
                headers => { 'Content-Type' => 'application/json' },
                json    => { test => 'data' },
            },
        );
    } qr/did not pass type constraint/;
}

sub invalid_uris_are_rejected : Test(1) ($self) {
    throws_ok {
        MonkWorld::API::Request->new(
            link_meta => {
                method  => 'POST',
                href    => '/RESOURCE WITH SPACE',
                headers => {},
                json    => { test => 'data' },
            },
        );
    } qr/did not pass type constraint/;
}