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
            create_node => {
                href => $self->url_for('create_node'),
                method => 'POST',
                headers => {
                    'Authorization' => 'Bearer %s',
                },
                json => {
                    node_id      => 'NODE_ID',       # Optional
                    node_type_id => 'NODE_TYPE_ID',  # Required
                    author_id    => 'AUTHOR_ID',     # Required
                    title        => 'NODE_TITLE',    # Required
                    doctext      => 'NODE_DOCTEXT'   # Required
                }
            },
            get_threads => {
                href => $self->url_for('get_threads'),
                method => 'GET',
            },
        },
    });
}