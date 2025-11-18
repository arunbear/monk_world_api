package MonkWorld::Test::Thread;

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

sub schema { 'thread_test' }

sub startup : Tests(startup) ($self) {
    $self->pg->db->insert('node_type', { id => NODE_TYPE_NOTE, name => 'note' });

    $self->{section_1} = $self->pg->db->insert(
        'node_type',
        { name => 'Section_1' },
        { returning => [qw(id name)] }
    )->hash;
    $self->{node_store} = {}; # store nodes by title
}

sub teardown : Tests(teardown) ($self) {
    $self->pg->db->query('TRUNCATE note, node');
}

sub a_thread_can_be_retrieved_by_id : Test(11) ($self) {
    my $t = $self->mojo;

    $self->_create_thread($self->{section_1}{id}, 'Thread_1');
    my $thread_id = $self->{node_store}{Thread_1}{id};

    # Get the threads using API::Request
    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta => $sitemap->{_links}{get_thread},
        with_auth_token => false,
    )
    ->add_uri_segment($thread_id);

    my $tx = $t->ua->build_tx($req->tx_args);

    note "Main tests start ...";
    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json = {
        "$self->{node_store}{Thread_1}{id}" => {
            title => 'Thread_1',
            created_at => re($expected_time),
            author_id  => $self->anonymous_user_id,
            author_username => 'Anonymous Monk',
            section_name => 'Section_1',
            reply => {
                "$self->{node_store}{'reply.Thread_1'}{id}" => {
                    title => 'reply.Thread_1',
                    created_at => re($expected_time),
                    author_id  => $self->anonymous_user_id,
                    author_username => 'Anonymous Monk',
                    reply => {
                        "$self->{node_store}{'reply.reply.Thread_1'}{id}" => {
                            title => 'reply.reply.Thread_1',
                            created_at => re($expected_time),
                            author_id  => $self->anonymous_user_id,
                            author_username => 'Anonymous Monk',
                        }
                    }
                }
            }
        }
    };

    my $result = $t->tx->res->json;
    cmp_deeply $result, $expected_json;
}

sub a_subthread_can_be_retrieved_by_id : Test(11) ($self) {
    my $t = $self->mojo;

    $self->_create_thread($self->{section_1}{id}, 'Thread_1');
    my $thread_id = "$self->{node_store}{'reply.Thread_1'}{id}";

    # Get the threads using API::Request
    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta => $sitemap->{_links}{get_thread},
        with_auth_token => false,
    )
    ->add_uri_segment($thread_id);

    my $tx = $t->ua->build_tx($req->tx_args);

    note "Main tests start ...";
    $t->request_ok($tx)
        ->status_is(HTTP_OK);

    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json = {
        "$self->{node_store}{'reply.Thread_1'}{id}" => {
            title           => 'reply.Thread_1',
            created_at      => re($expected_time),
            author_id       => $self->anonymous_user_id,
            author_username => 'Anonymous Monk',
            section_name    => 'Section_1',
            root_title      => 'Thread_1',
            root_id         => $self->{node_store}{Thread_1}{id},
            parent_title    => 'Thread_1',
            parent_id       => $self->{node_store}{Thread_1}{id},
            reply => {
                "$self->{node_store}{'reply.reply.Thread_1'}{id}" => {
                    title => 'reply.reply.Thread_1',
                    created_at => re($expected_time),
                    author_id  => $self->anonymous_user_id,
                    author_username => 'Anonymous Monk',
                }
            }
        }
    };

    my $result = $t->tx->res->json;
    cmp_deeply $result, $expected_json or explain $result;
}

sub a_subthread_of_a_subthread_can_be_retrieved_by_id : Test(11) ($self) {
    my $t = $self->mojo;

    $self->_create_thread($self->{section_1}{id}, 'Thread_1');
    my $thread_id = $self->{node_store}{'reply.reply.Thread_1'}{id};

    # Get the threads using API::Request
    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta => $sitemap->{_links}{get_thread},
        with_auth_token => false,
    )
    ->add_uri_segment($thread_id);

    my $tx = $t->ua->build_tx($req->tx_args);

    note "Main tests start ...";
    $t->request_ok($tx)->status_is(HTTP_OK);

    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json = {
        $thread_id => {
            title => 'reply.reply.Thread_1',
            created_at      => re($expected_time),
            author_id       => $self->anonymous_user_id,
            author_username => 'Anonymous Monk',
            section_name    => 'Section_1',
            root_title      => 'Thread_1',
            root_id         => $self->{node_store}{Thread_1}{id},
            parent_title    => 'reply.Thread_1',
            parent_id       => $self->{node_store}{'reply.Thread_1'}{id},
        }
    };
    my $result = $t->tx->res->json;
    cmp_deeply $result, $expected_json or explain $result;
}

# _create_thread method is now provided by MonkWorld::Test::Role::ThreadCreation