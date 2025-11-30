package MonkWorld::API;
our $VERSION = 0.001_001;
use v5.40;
use Mojo::Base 'Mojolicious';
use HTTP::Status 'HTTP_UNAUTHORIZED';
use MonkWorld::API::Pg;

# Add convenience methods to Mojo::Collection
use Mojo::Util 'monkey_patch';
monkey_patch 'Mojo::Collection',
    is_empty     => sub ($self) { $self->size == 0 },
    is_not_empty => sub ($self) { $self->size > 0 };

# This method will run once at server start
sub startup ($self) {
  $self->plugin('NotYAMLConfig');
  $self->configure_logging;
  $self->set_db_connection;

  # Router
  my $r = $self->routes;

  $r->get('/')->to('Root#index');
  $r->get('/health' => sub ($c) { $c->render(json => ['OK']) });

  $r->get('/thread/:id')->to('Node#get')->name('get_thread');
  $r->get('/threads')->to('Threads#index')->name('get_threads');
  $r->get('/search')->to('Search#index')->name('search');
  $r->get('/sections')->to('NodeType#index')->name('get_all_sections');

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
  $auth->post('/monk')->to('Monk#create')->name('create_monk');
  $auth->post('/node')->to('Node#create')->name('create_node');
}

sub configure_logging ($self) {
    my $config = $self->config;
    $self->log->path($config->{logger}{path});
    $self->log->level($config->{logger}{level});
}

sub set_db_connection ($self) {
    $self->helper(pg => sub {
        state $pg = MonkWorld::API::Pg::get_pg();
        return $pg;
    });
}
