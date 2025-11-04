package MonkWorld::API;
our $VERSION = 0.001_001;
use v5.40;
use Mojo::Base 'Mojolicious', -signatures;
use HTTP::Status 'HTTP_UNAUTHORIZED';

# Add convenience methods to Mojo::Collection
use Mojo::Util 'monkey_patch';
monkey_patch 'Mojo::Collection',
    is_empty     => sub ($self) { $self->size == 0 },
    is_not_empty => sub ($self) { $self->size > 0 };

# This method will run once at server start
sub startup ($self) {
  my $config = $self->plugin('NotYAMLConfig');
  $self->configure_logging;

  # Configure the application
  $self->secrets($config->{secrets});

  # Setup database
  $self->helper(pg => sub {
      state $pg = Mojo::Pg->new($ENV{MONKWORLD_PG_URL});
      return $pg;
  });

  # Router
  my $r = $self->routes;

  $r->get('/')->to('Root#index');
  $r->get('/health' => sub ($c) { $c->render(json => ['OK']) });

  # Protected routes
  my $auth = $r->under(sub ($c) {
      my $auth_header = $c->req->headers->authorization // '';
      my ($token) = $auth_header =~ /^Bearer (\S+)$/;

      return 1 if $token && $token eq ($ENV{MONKWORLD_AUTH_TOKEN} // '');

      $c->render(
          json   => { error => 'Unauthorized' },
          status => HTTP_UNAUTHORIZED
      );
      return undef;
  });

  $auth->post('/node-type')->to('NodeType#create')->name('create_node_type');
  $auth->post('/monk')->to('Monk#create');
  $auth->post('/node')->to('Node#create');
}

sub configure_logging ($self) {
    my $config = $self->config;
    $self->log->path($config->{logger}{path});
    $self->log->level($config->{logger}{level});
}
