package MonkWorld::Test::Search;

use v5.40;
use HTTP::Status qw(HTTP_OK HTTP_CREATED);
use MonkWorld::API::Constants qw(NODE_TYPE_NOTE NODE_TYPE_PERLQUESTION);
use MonkWorld::API::Request;
use Time::Piece;
use Time::Seconds qw(ONE_DAY);
use Role::Tiny::With;

use Test::Class::Most
    parent => 'MonkWorld::Test::Base';

with 'MonkWorld::Test::Role::ThreadCreation';

sub schema {'threads_test'}

sub startup :Tests(startup) ($self) {
    $self->pg->db->insert('node_type', { id => NODE_TYPE_NOTE, name => 'note' });

    $self->{section_1} = $self->pg->db->insert(
        'node_type',
        { name => 'Section_1' },
        { returning => [ qw(id name) ] }
    )->hash;
    $self->{section_2} = $self->pg->db->insert(
        'node_type',
        { name => 'Section_2' },
        { returning => [ qw(id name) ] }
    )->hash;
    $self->{node_store} = {}; # store nodes by title
}

sub teardown :Tests(teardown) ($self) {
    $self->pg->db->query('TRUNCATE note, node');
}

sub nodes_can_be_searched_by_content :Test(no_plan) ($self) {
    my $t = $self->mojo;

    $self->_create_thread(
        $self->{section_1}{id},
        'Book recommendations',
        [],
        [
            'The book "Modern Perl" by chromatic is a great introduction to modern Perl practices.',
            '"Perl Best Practices" by Damian Conway is a must-read for any serious Perl programmer.',
            '"Higher-Order Perl" by Mark Jason Dominus explores advanced functional programming in Perl.'
        ]
    );
    $self->_create_thread(
        $self->{section_2}{id},
        'Best Practices',
        [],
        [
            'Always use strict and warnings in your Perl code to catch common mistakes.',
            'Use meaningful variable names and include POD documentation for all subroutines.',
            'Write tests for your code and follow the principle of least surprise.'
        ]
    );

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