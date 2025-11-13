package MonkWorld::API::Controller::Threads;
use v5.40;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use MonkWorld::API::Constants qw(NODE_TYPE_NOTE NODE_TYPE_PERLQUESTION);
use MonkWorld::API::Model::Threads;

has threads_model => sub ($self) {
    MonkWorld::API::Model::Threads->new(pg => $self->pg, log => $self->log);
};

# GET /threads
# Returns threads grouped by section in the structure expected by the test
sub index ($self) {
    my $result = $self->threads_model->get_threads;

    return $self->render(
        json => $result,
    );
}