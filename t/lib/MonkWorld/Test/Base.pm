package MonkWorld::Test::Base;

use v5.40;
use Mojo::Pg;
use Sub::Override;
use Test::Mojo;
use Test::Class::Most
  attributes  => [qw/mojo pg/];

INIT { Test::Class->runtests }

sub db_prepare : Test(startup) ($self) {
    my $t = Test::Mojo->new('MonkWorld::API');
    $self->mojo($t);

    my $path = $t->app->home->child('migrations');
    my $pg = $t->app->pg;
    $self->pg($pg);

    $self->setup_schema;
    $pg->migrations->from_dir($path)->migrate;
}

sub setup_schema ($self) {
    my $schema = $self->schema;
    my $pg = $self->pg;
    $pg->search_path([$schema]);
    $pg->db->query("DROP SCHEMA IF EXISTS $schema CASCADE");
    $pg->db->query("CREATE SCHEMA $schema");
}

sub anonymous_user_id ($self) {
    return $self->pg->db->select('monk', ['id'], { username => 'Anonymous Monk' })->hash->{id};
}