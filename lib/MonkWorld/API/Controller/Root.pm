package MonkWorld::API::Controller::Root;
use v5.40;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub index ($self) {
    $self->res->headers->content_type("application/vnd.monkworld+json;version=$MonkWorld::API::VERSION");
    $self->render(json => {
        _links => {
            self => {
                href => '/'
            },
            create_node_type => {
                href => $self->url_for('create_node_type'),
                method => 'POST',
                headers => {
                    'Authorization' => 'Bearer %s'
                },
                json => {
                    name => 'NODE_TYPE_NAME',
                    id   => 'NODE_TYPE_ID',
                }
            },
            create_monk => {
                href => $self->url_for('create_monk'),
                method => 'POST',
                headers => {
                    'Authorization' => 'Bearer %s'
                },
                json => {
                    username => 'MONK_USERNAME',
                    id       => 'MONK_ID',
                }
            },
        },
    });
}