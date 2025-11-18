package MonkWorld::Test::Role::ThreadCreation;

use v5.40;
use Role::Tiny;
use namespace::autoclean;
use Test::More;
use HTTP::Status qw(HTTP_CREATED);
use MonkWorld::API::Constants 'NODE_TYPE_NOTE';

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

    return ($root, $first_reply, $second_reply);
}

__END__

=head1 NAME

MonkWorld::Test::Role::ThreadCreation - Role for creating test threads

=head1 DESCRIPTION

This role provides thread creation functionality for test classes.

=cut
