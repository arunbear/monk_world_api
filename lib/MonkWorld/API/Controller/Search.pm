package MonkWorld::API::Controller::Search;
use v5.40;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Mojo::JSON qw(decode_json encode_json);
use MonkWorld::API::Model::Search;

has search_model => sub ($self) {
    MonkWorld::API::Model::Search->new(pg => $self->pg, log => $self->log);
};

sub index ($self) {
    my $validation = $self->validation;
    $validation->optional('q')->size(1, 100);
    $validation->optional('limit')->num(1, 50);
    $validation->optional('after')->num(0, undef);

    if ($validation->has_error) {
        my %errors = map { $_ => [$validation->error($_)] } $validation->failed->@*;
        return $self->render(
            status => 400,
            json   => {
                error => 'Invalid parameters',
                details => \%errors
            }
        );
    }

    my $q     = $validation->param('q');
    my $limit = $validation->param('limit');
    my $after = $validation->param('after');

    my $results = $self->search_model->search($q,
        ($limit ? (limit => $limit) : ()),
        ($after ? (after => $after) : ())
    );

    return $self->render(
        json => $results
    );
}