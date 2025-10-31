package MonkWorld::Test::Note;

use v5.40;
use HTTP::Status qw(HTTP_CREATED HTTP_CONFLICT);
use MonkWorld::API::Constants qw(NODE_TYPE_NOTE NODE_TYPE_PERLQUESTION);
use Mojo::Pg::Transaction;

use Test::Class::Most
  parent => 'MonkWorld::Test::Base';

sub schema { 'note_test' }

sub a_note_can_be_created : Test(4) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    my $anon_user_id = $self->anonymous_user_id;

    my $parent_node = $t->post_ok(
        '/node' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            node_type_id => NODE_TYPE_PERLQUESTION,
            author_id    => $anon_user_id,
            title        => 'A Parent',
            doctext      => 'This is also the root',
        }
    )->status_is(HTTP_CREATED)->tx->res->json;

    my $parent_node_id = $parent_node->{id};
    my $root_node_id = $parent_node_id;
    my $created_at = $parent_node->{created_at};

    subtest 'without an ID' => sub {
        $t->post_ok(
            '/node' => {
                'Authorization' => "Bearer $auth_token"
            } => json => {
                node_type_id => NODE_TYPE_NOTE,
                author_id    => $anon_user_id,
                title        => 'Test Note',
                doctext      => 'This is a test note',
                root_node    => $root_node_id,
                parent_node  => $parent_node_id,
                created      => $created_at,
            }
        )
        ->header_like('Location' => qr{/node/\d+$})
        ->json_has('/id')
        ->json_has('/created_at')
        ->json_is('/title' => 'Test Note')
        ->json_is('/doctext' => 'This is a test note')
        ->json_is('/node_type_id' => NODE_TYPE_NOTE)
        ->json_is('/root_node' => $root_node_id)
        ->json_is('/parent_node' => $parent_node_id)
        ->json_is('/path' => "$parent_node_id." . $t->tx->res->json->{id})
        ;
    };

    subtest 'with an explicit ID' => sub {
        my $id = $t->tx->res->json->{id};
        ok $id > 0, 'ID is a positive integer';
        my $explicit_id = $id + 2; # better than 1 as auto increment would give a false pass

        $t->post_ok(
            '/node' => {
                'Authorization' => "Bearer $auth_token"
            } => json => {
                node_id      => $explicit_id,
                node_type_id => NODE_TYPE_NOTE,
                author_id    => $anon_user_id,
                title        => 'Test Note with ID',
                doctext      => 'This is a test note with explicit ID',
                root_node    => $root_node_id,
                parent_node  => $parent_node_id,
                created      => $created_at,
            }
        )
        ->status_is(HTTP_CREATED)
        ->header_like('Location' => qr{/node/$explicit_id$})
        ->json_is('/id' => $explicit_id)
        ->json_has('/created_at')
        ->json_is('/title' => 'Test Note with ID')
        ->json_is('/doctext' => 'This is a test note with explicit ID')
        ->json_is('/node_type_id' => NODE_TYPE_NOTE)
        ->json_is('/root_node' => $root_node_id)
        ->json_is('/parent_node' => $parent_node_id)
        ->json_is('/path' => "$parent_node_id.$explicit_id");
    };
}

sub a_note_cannot_be_created_if_parent_node_does_not_exist : Test(3) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
        or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    my $non_existing_node = $self->max_node_id + 1;
    $t->post_ok(
        '/node' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            node_type_id => NODE_TYPE_NOTE,
            author_id    => $self->anonymous_user_id,
            title        => 'Test Note with no root',
            doctext      => 'No root',
            parent_node  => $non_existing_node,
            root_node    => $non_existing_node,
        }
    )
    ->json_like('/error' => qr/parent_node.+ is not present/)
    ->status_is(HTTP::Status::HTTP_UNPROCESSABLE_ENTITY);
}

sub a_note_cannot_be_created_if_its_non_root_parent_is_not_in_note_table : Test(5) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    # First create a valid parent node
    my $parent = $t->post_ok(
        '/node' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            node_type_id => NODE_TYPE_PERLQUESTION,
            author_id    => $self->anonymous_user_id,
            title        => 'Parent Node',
            doctext      => 'This is a parent node',
        }
    )->status_is(HTTP_CREATED)
     ->tx->res->json;

    $t->post_ok(
        '/node' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            node_type_id => NODE_TYPE_NOTE,
            author_id    => $self->anonymous_user_id,
            title        => 'Test Note with no root',
            doctext      => 'No root',
            parent_node  => $parent->{id},
            root_node    => $parent->{id} + 2,
        }
    )
    ->status_is(HTTP::Status::HTTP_UNPROCESSABLE_ENTITY)
    ->json_like('/error' => qr/Non root parent.+ not present/)
    ;
}

sub a_note_can_be_created_as_reply_to_reply : Test(10) ($self) {
    my $t = $self->mojo;

    my $auth_token = $ENV{MONKWORLD_AUTH_TOKEN}
      or return('Expected MONKWORLD_AUTH_TOKEN in %ENV');

    note 'Create a root node';
    my $root = $t->post_ok(
        '/node' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            node_type_id => NODE_TYPE_PERLQUESTION,
            author_id    => $self->anonymous_user_id,
            title        => 'Root Question',
            doctext      => 'This is the root question',
        },
    )->status_is(HTTP_CREATED)
     ->tx->res->json;

    note 'Create first reply to root';
    my $first_reply = $t->post_ok(
        '/node' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            node_type_id => NODE_TYPE_NOTE,
            author_id    => $self->anonymous_user_id,
            title        => 'First Reply',
            doctext      => 'This is the first reply',
            parent_node  => $root->{id},
            root_node    => $root->{id},
        }
    )->status_is(HTTP_CREATED)
     ->tx->res->json;

    note 'Create a reply to the first reply';
    $t->post_ok(
        '/node' => {
            'Authorization' => "Bearer $auth_token"
        } => json => {
            node_type_id => NODE_TYPE_NOTE,
            author_id    => $self->anonymous_user_id,
            title        => 'Reply to Reply',
            doctext      => 'This is a reply to the first reply',
            parent_node  => $first_reply->{id},
            root_node    => $root->{id},
        }
    )->status_is(HTTP_CREATED)
     ->json_has('/id')
     ->json_is('/parent_node' => $first_reply->{id})
     ->json_is('/root_node' => $root->{id})
     ->json_is('/path' => sprintf('%d.%d.%d', $root->{id}, $first_reply->{id}, $t->tx->res->json->{id}));
}

sub max_node_id ($self) {
    return $self->pg->db->query('SELECT MAX(id) FROM node')->hash->{max};
}