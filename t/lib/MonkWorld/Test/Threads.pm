package MonkWorld::Test::Threads;

use v5.40;
use HTTP::Status qw(HTTP_OK HTTP_CREATED);
use MonkWorld::API::Constants qw(NODE_TYPE_NOTE NODE_TYPE_PERLQUESTION);
use MonkWorld::API::Request;
use Time::Piece;
use Time::Seconds qw(ONE_DAY);

use Test::Class::Most
  parent => 'MonkWorld::Test::Base';

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

    # Define expected structure with actual node titles and IDs
    my $expected = {
        Section_1 => {
            "$self->{node_store}{Thread_1}{id}" => {
                title => 'Thread_1',
                reply => {
                    "$self->{node_store}{'reply.Thread_1'}{id}" => {
                        title => 'reply.Thread_1',
                        reply => {
                            "$self->{node_store}{'reply.reply.Thread_1'}{id}" => {
                                title => 'reply.reply.Thread_1',
                            }
                        }
                    }
                }
            }
        },
        Section_2 => {
            "$self->{node_store}{'Thread_2'}{id}" => {
                title => 'Thread_2',
                reply => {
                    "$self->{node_store}{'reply.Thread_2'}{id}" => {
                        title => 'reply.Thread_2',
                        reply => {
                            "$self->{node_store}{'reply.reply.Thread_2'}{id}" => {
                                title => 'reply.reply.Thread_2',
                            }
                        }
                    }
                }
            }
        }
    };

    # Get and verify the actual response
    my $result = $t->tx->res->json;
    eq_or_diff $result, $expected;
}

sub threads_can_be_retrieved_so_long_as_they_have_recent_replies : Test(no_plan) ($self) {
    my $t = $self->mojo;

    {
        my $time = localtime;
        my $four_days_ago = ($time - 4 * ONE_DAY)->datetime;
        my $two_days_ago  = ($time - 2 * ONE_DAY)->datetime;

        $self->_create_thread(
            $self->{section_1}{id},
            'Thread_1',
            [ $four_days_ago, $two_days_ago ],
        );
    }

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

    my $expected = {
        Section_1 => {
            "$self->{node_store}{Thread_1}{id}" => {
                title => 'Thread_1',
                reply => {
                    "$self->{node_store}{'reply.Thread_1'}{id}" => {
                        title => 'reply.Thread_1',
                        reply => {
                            "$self->{node_store}{'reply.reply.Thread_1'}{id}" => {
                                title => 'reply.reply.Thread_1',
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

# Creates a thread with replies, deriving reply titles and text from the thread title
#
# Parameters:
#   $section_id - ID of the section to create the thread in
#   $thread_title - Main title for the thread (required)
#   $creation_dates - An optional array of creation dates, one for each node being created.
#     A missing value means no date is passed to the API.
#
# Returns: List of created nodes (root, first_reply, second_reply)
sub _create_thread ($self, $section_id, $thread_title, $creation_dates = []) {
    my $t = $self->mojo;

    note "Create a root node $thread_title in section $section_id";
    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request
        ->new(link_meta => $sitemap->{_links}{create_node})
        ->update_json_entries(
            node_type_id => $section_id,
            author_id    => $self->anonymous_user_id,
            title        => $thread_title,
            doctext      => "Discussion about: $thread_title",
            # Optional created timestamp for root
            (defined $creation_dates->[0]
                ? (created => $creation_dates->[0])
                : ()),
        )
        ->ignore_json_kv('node_id');

    my $tx = $t->ua->build_tx($req->tx_args);
    my $root = $t->request_ok($tx)
        ->status_is(HTTP_CREATED)
        ->tx->res->json;
    $self->{node_store}{$thread_title} = $root;

    note 'Create first reply to root';
    $req = MonkWorld::API::Request
        ->new(link_meta => $sitemap->{_links}{create_node})
        ->update_json_entries(
            node_type_id => NODE_TYPE_NOTE,
            author_id    => $self->anonymous_user_id,
            title        => "reply.$thread_title",
            doctext      => "Further discussion about: $thread_title",
            parent_node  => $root->{id},
            root_node    => $root->{id},
            # Optional created timestamp for first reply
            (defined $creation_dates->[1]
                ? (created => $creation_dates->[1])
                : ()),
        )
        ->ignore_json_kv('node_id');

    $tx = $t->ua->build_tx($req->tx_args);
    my $first_reply = $t->request_ok($tx)
        ->status_is(HTTP_CREATED)
        ->tx->res->json;
    $self->{node_store}{"reply.$thread_title"} = $first_reply;

    note 'Create a reply to the first reply';
    $req = MonkWorld::API::Request
        ->new(link_meta => $sitemap->{_links}{create_node})
        ->update_json_entries(
            node_type_id => NODE_TYPE_NOTE,
            author_id    => $self->anonymous_user_id,
            title        => "reply.reply.$thread_title",
            doctext      => "Even more discussion about: $thread_title",
            parent_node  => $first_reply->{id},
            root_node    => $root->{id},
            # Optional created timestamp for second reply
            (defined $creation_dates->[2]
                ? (created => $creation_dates->[2])
                : ()),
        )
        ->ignore_json_kv('node_id');

    $tx = $t->ua->build_tx($req->tx_args);
    my $second_reply = $t->request_ok($tx)->status_is(HTTP_CREATED)->tx->res->json;
    $self->{node_store}{"reply.reply.$thread_title"} = $second_reply;
}
