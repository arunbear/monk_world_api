package MonkWorld::Test::Threads;

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

sub schema { 'threads_test' }

sub startup : Tests(startup) ($self) {
    $self->pg->db->insert('node_type', { id => NODE_TYPE_NOTE, name => 'note' });

    $self->{section_1} = $self->pg->db->insert(
        'node_type',
        { name => 'Section_1' },
        { returning => [qw(id name)] }
    )->hash;
    $self->{section_2} = $self->pg->db->insert(
        'node_type',
        { name => 'Section_2' },
        { returning => [qw(id name)] }
    )->hash;
    $self->{node_store} = {}; # store nodes by title
}

sub teardown : Tests(teardown) ($self) {
    $self->pg->db->query('TRUNCATE note, node');
}

sub trees_of_nodes_can_be_retrieved_grouped_by_section : Test(no_plan) ($self) {
    my $t = $self->mojo;

    $self->_create_thread(
        $self->{section_1}{id},
        'Thread_1'
    );
    $self->_create_thread(
        $self->{section_2}{id},
        'Thread_2'
    );

    # Get the threads using API::Request
    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta => $sitemap->{_links}{get_threads},
        with_auth_token => false,
    );
    my $tx = $t->ua->build_tx($req->tx_args);

    note "Main tests ...";
    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $expected_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off

    my $expected_json = {
        Section_1 => {
            "$self->{node_store}{Thread_1}{id}" => {
                title => 'Thread_1',
                created_at => re($expected_time),
                author_id  => $self->anonymous_user_id,
                author_username => 'Anonymous Monk',
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
        },
        Section_2 => {
            "$self->{node_store}{'Thread_2'}{id}" => {
                title => 'Thread_2',
                created_at => re($expected_time),
                author_id  => $self->anonymous_user_id,
                author_username => 'Anonymous Monk',
                reply => {
                    "$self->{node_store}{'reply.Thread_2'}{id}" => {
                        title => 'reply.Thread_2',
                        created_at => re($expected_time),
                        author_id  => $self->anonymous_user_id,
                        author_username => 'Anonymous Monk',
                        reply => {
                            "$self->{node_store}{'reply.reply.Thread_2'}{id}" => {
                                title => 'reply.reply.Thread_2',
                                created_at => re($expected_time),
                                author_id  => $self->anonymous_user_id,
                                author_username => 'Anonymous Monk',
                            }
                        }
                    }
                }
            }
        }
    };

    # Get and verify the actual response
    my $result = $t->tx->res->json;
    cmp_deeply $result, $expected_json;
}

sub recent_replies_can_be_retrieved_along_with_their_ancestors : Test(no_plan) ($self) {
    my $t = $self->mojo;

    my $time = localtime;
    my $four_days_ago = ($time - 4 * ONE_DAY);
    my $two_days_ago  = ($time - 2 * ONE_DAY);

    $self->_create_thread(
        $self->{section_1}{id},
        'Thread_1',
        [ $four_days_ago->datetime, $two_days_ago->datetime ],
    );

    # Get the threads using API::Request
    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta => $sitemap->{_links}{get_threads},
        with_auth_token => false,
    );
    my $tx = $t->ua->build_tx($req->tx_args);

    note "Creation-dated test ...";
    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $expected_now_time = localtime->strftime('%Y-%m-%d %H:%M'); # Pg timestamp might be a second off
    my $expected = {
        Section_1 => {
            "$self->{node_store}{Thread_1}{id}" => {
                title => 'Thread_1',
                created_at => $four_days_ago->date.' '.$four_days_ago->time,
                author_id  => $self->anonymous_user_id,
                author_username => 'Anonymous Monk',
                reply => {
                    "$self->{node_store}{'reply.Thread_1'}{id}" => {
                        title => 'reply.Thread_1',
                        created_at => $two_days_ago->date.' '.$two_days_ago->time,
                        author_id  => $self->anonymous_user_id,
                        author_username => 'Anonymous Monk',
                        reply => {
                            "$self->{node_store}{'reply.reply.Thread_1'}{id}" => {
                                title => 'reply.reply.Thread_1',
                                created_at => re($expected_now_time),
                                author_id  => $self->anonymous_user_id,
                                author_username => 'Anonymous Monk',
                            }
                        }
                    }
                }
            }
        },
    };

    my $result = $t->tx->res->json;
    cmp_deeply $result, $expected;
}

sub nodes_are_not_retrieved_outside_the_cutoff_interval : Test(no_plan) ($self) {
    my $t = $self->mojo;

    my $time = localtime;
    my $six_days_ago  = ($time - 6 * ONE_DAY);
    my $four_days_ago = ($time - 4 * ONE_DAY);
    my $two_days_ago  = ($time - 2 * ONE_DAY);

    $self->_create_thread(
        $self->{section_1}{id},
        'Thread_1',
        [ $six_days_ago->datetime, $four_days_ago->datetime, $two_days_ago->datetime ],
    );

    # Get the threads using API::Request
    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta => $sitemap->{_links}{get_threads},
        with_auth_token => false,
    );
    my $tx = $t->ua->build_tx($req->tx_args);

    $t->request_ok($tx)
      ->status_is(HTTP_OK);

    my $expected = { };
    my $result = $t->tx->res->json;
    eq_or_diff $result, $expected;
}

sub the_cutoff_interval_can_be_specified_as_a_request_param : Test(no_plan) ($self) {
    my $t = $self->mojo;

    my $time = localtime;
    my $six_days_ago  = ($time - 6 * ONE_DAY); # all of these
    my $four_days_ago = ($time - 4 * ONE_DAY); # are older than
    my $two_days_ago  = ($time - 2 * ONE_DAY); # the default date cutoff

    $self->_create_thread(
        $self->{section_1}{id},
        'Thread_1',
        [ $six_days_ago->datetime, $four_days_ago->datetime, $two_days_ago->datetime ],
    );

    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request->new(
        link_meta => $sitemap->{_links}{get_threads},
        with_auth_token => false,
    )
    ->update_form_entries(days => 7);

    my $tx = $t->ua->build_tx($req->tx_args);
    $t->request_ok($tx)->status_is(HTTP_OK);

    my $expected = {
        Section_1 => {
            "$self->{node_store}{Thread_1}{id}" => {
                title => 'Thread_1',
                created_at => $six_days_ago->date.' '.$six_days_ago->time,
                author_id  => $self->anonymous_user_id,
                author_username => 'Anonymous Monk',
                reply => {
                    "$self->{node_store}{'reply.Thread_1'}{id}" => {
                        title => 'reply.Thread_1',
                        created_at => $four_days_ago->date.' '.$four_days_ago->time,
                        author_id  => $self->anonymous_user_id,
                        author_username => 'Anonymous Monk',
                        reply => {
                            "$self->{node_store}{'reply.reply.Thread_1'}{id}" => {
                                title => 'reply.reply.Thread_1',
                                created_at => $two_days_ago->date.' '.$two_days_ago->time,
                                author_id  => $self->anonymous_user_id,
                                author_username => 'Anonymous Monk',
                            }
                        }
                    }
                }
            }
        },
    };

    my $result = $t->tx->res->json;
    eq_or_diff $result, $expected;
}