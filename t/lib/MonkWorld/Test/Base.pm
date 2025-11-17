package MonkWorld::Test::Base;

use v5.40;
use Mojo::Pg;
use MonkWorld::API::Request;
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
    $self->create_anonymous_user;
}

sub create_anonymous_user ($self) {
    $self->pg->db->insert('monk', { username => 'Anonymous Monk' });
}

sub setup_schema ($self) {
    my $schema = $self->schema;
    my $pg = $self->pg;
    $pg->search_path([$schema, 'public']);
    $pg->db->query("DROP SCHEMA IF EXISTS $schema CASCADE");
    $pg->db->query("CREATE SCHEMA $schema");
}

sub anonymous_user_id ($self) {
    return $self->pg->db->select('monk', ['id'], { username => 'Anonymous Monk' })->hash->{id};
}

sub get_sitemap ($self) {
    return $self->mojo->get_ok('/')->tx->res->json;
}

sub create_node_type ($self, $name) {
    my $sitemap = $self->get_sitemap;
    my $req = MonkWorld::API::Request
        ->new(link_meta => $sitemap->{_links}{create_node_type})
        ->update_json_kv(name => $name)
        ->ignore_json_kv('id');

    my $tx = $self->mojo->ua->build_tx($req->tx_args);
    $self->mojo->request_ok($tx)->tx->res->json;
}