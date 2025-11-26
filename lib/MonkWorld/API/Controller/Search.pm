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
    $validation->optional('before')->num(0, undef);
    $validation->optional('sort')->in(qw(up down));
    $validation->optional('os')->num(0, undef); # only some sections
    $validation->optional('xs')->num(0, undef); # exclude sections

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

    my $q       = $validation->param('q');
    my $limit   = $validation->param('limit');
    my $after   = $validation->param('after');
    my $before  = $validation->param('before');
    my $sort    = $validation->param('sort');
    my $include_sections = $validation->every_param('os');
    my $exclude_sections = $validation->every_param('xs');

    my $results = $self->search_model->search(
        $q,
        ($sort      ? (sort => $sort)       : ()),
        ($limit     ? (limit => $limit)     : ()),
        ($after     ? (after => $after)     : ()),
        ($before    ? (before => $before)   : ()),
        (@$include_sections ? (include_sections => $include_sections) : ()),
        (@$exclude_sections ? (exclude_sections => $exclude_sections) : ()),
    );

    return $self->render(
        json => $results
    );
}