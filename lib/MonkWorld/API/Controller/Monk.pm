package MonkWorld::API::Controller::Monk;
use v5.40;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util 'trim';
use HTTP::Status qw(HTTP_UNPROCESSABLE_CONTENT HTTP_CREATED HTTP_CONFLICT);
use MonkWorld::API::Model::Monk;

has 'monk_model' => sub ($self) {
    MonkWorld::API::Model::Monk->new(pg => $self->pg, log => $self->log);
};

sub create ($self) {
    my $data = $self->req->json;

    my $validator = Mojolicious::Validator->new;
    my $v = $validator->validation;
    $v->input($data);
    $v->required('username', 'not_empty')->like(qr/^\S+/);
    $v->optional('id')->num(1, undef);

    if ($v->has_error('username')) {
        return $self->render(
            json   => { error => 'username is required' },
            status => HTTP_UNPROCESSABLE_CONTENT
        );
    }
    if ($v->has_error('id')) {
        return $self->render(
            json   => { error => 'ID must be a positive integer' },
            status => HTTP_UNPROCESSABLE_CONTENT
        );
    }

    my $monk_data = {
        username => trim($data->{username}),
    };

    if (exists $data->{id}) {
        $monk_data->{id} = $data->{id};
    }

    my $collection = $self->monk_model->create($monk_data);

    if ($collection->is_empty) {
        return $self->render(
            json   => { error => 'Username already exists' },
            status => HTTP_CONFLICT
        );
    }

    my $monk = $collection->first;

    $self->res->headers->location("/monk/$monk->{id}");
    $self->render(
        json   => $monk,
        status => HTTP_CREATED
    );
}
