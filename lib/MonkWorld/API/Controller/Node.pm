package MonkWorld::API::Controller::Node;

use v5.40;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use HTTP::Status qw(HTTP_CREATED HTTP_BAD_REQUEST HTTP_CONFLICT HTTP_UNPROCESSABLE_ENTITY);
use Mojo::JSON qw(decode_json);
use MonkWorld::API::Model::Node;

has node_model => sub ($self) {
    MonkWorld::API::Model::Node->new(pg => $self->pg, log => $self->log);
};

sub create ($self) {
    my $data = $self->req->json;

    # Validate required fields
    return $self->render(
        json   => { error => 'node_type_id, title, and doctext are required' },
        status => HTTP_BAD_REQUEST
    ) unless $data->{node_type_id} && $data->{title} && $data->{doctext};

    my $collection;
    try {
        $collection = $self->node_model->create($data);
    }
    catch ($error) {
        $self->log->error(trim $error);
        return $self->render(
            json   => { error => $error },
            status => HTTP_UNPROCESSABLE_ENTITY
        );
    }

    if ($collection->size == 0) {
        return $self->render(
            json   => { error => 'Node with this ID already exists' },
            status => HTTP_CONFLICT
        );
    }

    my $node = $collection->first;
    $self->res->headers->location("/node/$node->{id}");
    $self->render(
        json   => $node,
        status => HTTP_CREATED
    );
}

sub get ($self) {
    my $node_id = $self->stash('id');
    my $node = $self->node_model->get_thread($node_id);
    $self->render(json => $node);
}