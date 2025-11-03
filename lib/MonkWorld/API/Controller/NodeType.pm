package MonkWorld::API::Controller::NodeType;
use v5.40;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use HTTP::Status qw(HTTP_BAD_REQUEST HTTP_CREATED HTTP_CONFLICT);
use MonkWorld::API::Model::NodeType;

has node_type_model => sub ($self) {
    MonkWorld::API::Model::NodeType->new(pg => $self->pg, log => $self->log);
};

sub create ($self) {
    my $data = $self->req->json;

    # Validate input
    return $self->render(
        json   => { error => 'name is required' },
        status => HTTP_BAD_REQUEST
    ) unless $data->{name};

    # Prepare node type data
    my $node_data = {
        name => $data->{name},
    };

    # Include ID if provided
    $node_data->{id} = $data->{id} if exists $data->{id};

    my $collection = $self->node_type_model->create($node_data);

    if ($collection->is_empty) {
        return $self->render(
            json   => { error => 'Node type with this name already exists' },
            status => HTTP_CONFLICT
        );
    }

    my $node_type = $collection->first;
    $self->res->headers->location("/node-type/$node_type->{id}");
    $self->render(
        json   => $node_type,
        status => HTTP_CREATED
    );
}
