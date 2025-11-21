package MonkWorld::API::Controller::Search;
use v5.40;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Mojo::JSON qw(decode_json encode_json);
use MonkWorld::API::Model::Search;

has search_model => sub ($self) {
    MonkWorld::API::Model::Search->new(pg => $self->pg, log => $self->log);
};

sub index ($self) {
    my $q = $self->param('q');
    my $limit = $self->param('limit') // 50;
    my $after = $self->param('after');

    $limit = $limit > 50 ? 50 : $limit;  # Enforce maximum limit

    my $results = $self->search_model->search($q, $limit, $after);

    return $self->render(
        json => $results
    );
}