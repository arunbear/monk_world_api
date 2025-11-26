package MonkWorld::Test::Search;

use v5.40;
use HTTP::Status qw(HTTP_OK);
use MonkWorld::API::Constants qw(NODE_TYPE_NOTE);
use MonkWorld::API::Request;
use Time::Piece;
use Role::Tiny::With;

use Test::Class::Most
    parent => 'MonkWorld::Test::Base';

with 'MonkWorld::Test::Role::ThreadCreation';

sub schema {'threads_test'}

sub startup :Tests(startup) ($self) {
    $self->pg->db->insert('node_type', { id => NODE_TYPE_NOTE, name => 'note' });

    # Store nodes by title, otherwise we'd have to use specific IDs in the tests.
    # We need to use unique test titles for this to work.
    $self->{node_store} = {};

    foreach my $n (1 .. 3) {
        my $section = "Section_$n";
        $self->{$section} = $self->pg->db->insert(
            'node_type',
            { name => $section },
            { returning => [ qw(id name) ] }
        )->hash;
    }
}

sub teardown :Tests(teardown) ($self) {
    $self->pg->db->query('TRUNCATE note, node');
}

sub nodes_can_be_searched_by_content :Test(25) ($self) {
    my $t = $self->mojo;

    $self->_create_test_threads();

    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta       => $sitemap->{_links}{search},
        with_auth_token => false,
    )
        ->update_form_entries(
        q => 'Best Practices',
    );
    my $tx = $t->ua->build_tx($req->tx_args);

    note "Main tests ...";
    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $result = $tx->res->json;
    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json =
        [
            {
                'author_username' => 'Anonymous Monk',
                author_id         => $self->anonymous_user_id,
                'created_at'      => re($expected_time),
                'id'              => $self->{node_store}{'Best Practices'}{id},
                section_name      => 'Section_2',
                'title'           => 'Best Practices'
            },
            {
                'author_username' => 'Anonymous Monk',
                author_id         => $self->anonymous_user_id,
                'created_at'      => re($expected_time),
                'id'              => $self->{node_store}{'reply.Book recommendations'}{id},
                section_name      => 'Section_1',
                'title'           => 'reply.Book recommendations'
            },
        ]
    ;
    cmp_deeply $result, $expected_json, or diag explain $result;
}

sub content_can_be_searched_using_web_search_operators :Test(25) ($self) {
    $self->_create_test_threads();

    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta       => $sitemap->{_links}{search},
        with_auth_token => false,
    )
    ->update_form_entries(
        q => q{ "Best Practices" OR Perl -functional },
    );
    my $t = $self->mojo;
    my $tx = $t->ua->build_tx($req->tx_args);

    note "Testing web search operators...";
    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $result = $tx->res->json;
    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M');

    my $expected_json = [
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'Best Practices'}{id},
            section_name      => 'Section_2',
            'title'           => 'Best Practices'
        },
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'reply.Book recommendations'}{id},
            'section_name'    => 'Section_1',
            'title'           => 'reply.Book recommendations'
        },
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'Book recommendations'}{id},
            'section_name'    => 'Section_1',
            'title'           => 'Book recommendations'
        }
    ];
    cmp_deeply $result, $expected_json, or explain $result;
}

sub searches_can_be_limited_by_number :Test(25) ($self) {
    my $t = $self->mojo;

    $self->_create_test_threads();

    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta       => $sitemap->{_links}{search},
        with_auth_token => false,
    )
    ->update_form_entries(
        q => 'Practices',
        limit => 3,
    );
    my $tx = $t->ua->build_tx($req->tx_args);

    note "Main tests ...";
    $t->request_ok($tx)
        ->status_is(HTTP_OK);

    my $result = $tx->res->json;
    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json = [
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'reply.reply.Best Practices'}{id},
            'section_name'    => 'Section_2',
            'title'           => 'reply.reply.Best Practices'
        },
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'reply.Best Practices'}{id},
            'section_name'    => 'Section_2',
            'title'           => 'reply.Best Practices'
        },
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'Best Practices'}{id},
            'section_name'    => 'Section_2',
            'title'           => 'Best Practices'
        }
    ]
    ;
    cmp_deeply $result, $expected_json, or diag explain $result;
}

sub searches_can_start_from_before_a_specific_node :Test(25) ($self) {
    $self->_create_test_threads();

    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta       => $sitemap->{_links}{search},
        with_auth_token => false,
    )
    ->update_form_entries(
        q => 'Practices',
        limit => 2,
        before => $self->{node_store}{'Best Practices'}{id},
    );
    my $t = $self->mojo;
    my $tx = $t->ua->build_tx($req->tx_args);

    note "Main tests ...";
    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $result = $tx->res->json;
    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json = [
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'reply.Book recommendations'}{id},
            'section_name'    => 'Section_1',
            'title'           => 'reply.Book recommendations'
        },
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'Book recommendations'}{id},
            'section_name'    => 'Section_1',
            'title'           => 'Book recommendations'
        }
    ];
    cmp_deeply $result, $expected_json or explain $result;
}

sub search_results_can_be_listed_in_ascending_order :Test(25) ($self) {
    $self->_create_test_threads();

    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta       => $sitemap->{_links}{search},
        with_auth_token => false,
    )
    ->update_form_entries(
        q => 'Best Practices',
        sort => 'up',
    );
    my $t = $self->mojo;
    my $tx = $t->ua->build_tx($req->tx_args);

    note "Main tests ...";
    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $result = $tx->res->json;
    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json =
        [
            {
                'author_username' => 'Anonymous Monk',
                author_id         => $self->anonymous_user_id,
                'created_at'      => re($expected_time),
                'id'              => $self->{node_store}{'reply.Book recommendations'}{id},
                section_name      => 'Section_1',
                'title'           => 'reply.Book recommendations'
            },
            {
                'author_username' => 'Anonymous Monk',
                author_id         => $self->anonymous_user_id,
                'created_at'      => re($expected_time),
                'id'              => $self->{node_store}{'Best Practices'}{id},
                section_name      => 'Section_2',
                'title'           => 'Best Practices'
            },
        ]
    ;
    cmp_deeply $result, $expected_json, or explain $result;
}

sub searches_can_start_from_after_a_specific_node :Test(25) ($self) {
    $self->_create_test_threads();

    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta       => $sitemap->{_links}{search},
        with_auth_token => false,
    )
    ->update_form_entries(
        q => 'Practices',
        sort => 'up',
        after => $self->{node_store}{'Best Practices'}{id},
    );
    my $t = $self->mojo;
    my $tx = $t->ua->build_tx($req->tx_args);

    note "Start main tests ...";
    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $result = $tx->res->json;
    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json = [
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'reply.Best Practices'}{id},
            'section_name'    => 'Section_2',
            'title'           => 'reply.Best Practices'
        },
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'reply.reply.Best Practices'}{id},
            'section_name'    => 'Section_2',
            'title'           => 'reply.reply.Best Practices'
        }
    ];
    cmp_deeply $result, $expected_json, or explain $result;
}

sub searches_can_be_limited_by_section :Test(25) ($self) {
    $self->_create_test_threads();

    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta       => $sitemap->{_links}{search},
        with_auth_token => false,
    )
    ->update_form_entries(
        q => 'test',
        os => [$self->{Section_1}{id}, $self->{Section_2}{id}],
    );
    my $t = $self->mojo;
    my $tx = $t->ua->build_tx($req->tx_args);

    note "Start main tests ...";
    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $result = $tx->res->json;
    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json = [
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'reply.reply.Best Practices'}{id},
            'section_name'    => 'Section_2',
            'title'           => 'reply.reply.Best Practices'
        },
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'Book recommendations'}{id},
            'section_name'    => 'Section_1',
            'title'           => 'Book recommendations'
        }
    ];
    cmp_deeply $result, $expected_json, or explain $result;
}

sub searches_can_skip_certain_sections :Test(25) ($self) {
    $self->_create_test_threads();

    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta       => $sitemap->{_links}{search},
        with_auth_token => false,
    )
    ->update_form_entries(
        q => 'test',
        xs => [$self->{Section_1}{id}, $self->{Section_2}{id}],
    );
    my $t = $self->mojo;
    my $tx = $t->ua->build_tx($req->tx_args);

    note "Start main tests ...";
    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $result = $tx->res->json;
    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json = [
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'reply.reply.Other Testing Frameworks'}{id},
            'section_name'    => 'Section_3',
            'title'           => 'reply.reply.Other Testing Frameworks'
        },
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'reply.Other Testing Frameworks'}{id},
            'section_name'    => 'Section_3',
            'title'           => 'reply.Other Testing Frameworks'
        },
        {
            'author_id'       => $self->anonymous_user_id,
            'author_username' => 'Anonymous Monk',
            'created_at'      => re($expected_time),
            'id'              => $self->{node_store}{'Other Testing Frameworks'}{id},
            'section_name'    => 'Section_3',
            'title'           => 'Other Testing Frameworks'
        }
    ];
    cmp_deeply $result, $expected_json, or explain $result;
}

sub _create_test_threads ($self) {
    $self->_create_thread(
        $self->{Section_1}{id},
        'Book recommendations',
        [],
        [
            q{"Perl Testing: A Developer's Notebook" by chromatic is a great introduction to Perl testing practices.},
            q{"Perl Best Practices" by Damian Conway is a must-read for any serious Perl programmer.},
            q{"Higher-Order Perl" by Mark Jason Dominus explores advanced functional programming in Perl.}
        ]
    );
    $self->_create_thread(
        $self->{Section_2}{id},
        'Best Practices',
        [],
        [
            'Always use strict and warnings in your Perl code to catch common mistakes.',
            'Use meaningful variable names and include POD documentation for all subroutines.',
            'Write tests for your code and follow the principle of least surprise.'
        ]
    );
    $self->_create_thread(
        $self->{Section_3}{id}, # test section inclusion and exclusion
        'Other Testing Frameworks',
        [],
        [
            'Jest: A delightful JavaScript Testing Framework with a focus on simplicity',
            'Pytest: A mature full-featured Python testing tool',
            'JUnit: A simple framework to write repeatable tests in Java'
        ]
    );
}
