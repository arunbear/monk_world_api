package MonkWorld::API::Model::Search;
use v5.40;
use Data::Dump 'dump';
use DBIx::PreQL;
use Mojo::Base 'MonkWorld::API::Model::Base';
use Mojo::Util qw(trim);

sub search ($self, $query, %params) {
    my $limit = $params{limit} // 50;
    my $sort  = $params{sort} // 'down';

    my $include_sections = $params{include_sections} // [];
    my $exclude_sections = $params{exclude_sections} // [];

    $self->log->debug("Searching for: $query with parameters: " . (dump %params));
    $query = trim($query);
    return [] unless $query;

    $limit = 50 if $limit > 50; # Enforce maximum limit
    my %data = (
        limit  => $limit,
        query  => $query,
        before => $params{before},
        after  => $params{after},
        sql_ord => \($sort eq 'down' ? 'DESC' : 'ASC'),
    );

    if ($include_sections->@*) {
        $data{sections_in} = $include_sections;
    }
    if ($exclude_sections->@*) {
        $data{sections_not_in} = $exclude_sections;
    }

    my $template = <<~'SQL';
    *   SELECT
    *       n.id,
    *       n.title,
    *       n.created_at,
    *       m.id as author_id,
    *       m.username as author_username,
    *       s.name as section_name
    *   FROM node n
    *   JOIN monk m ON n.author_id = m.id
    *   JOIN node_type nt ON n.node_type_id = nt.id
    *   JOIN node r ON r.id = (subpath(n.path, 0, 1))::text::bigint
    *   JOIN node_type s ON s.id = r.node_type_id
    *   WHERE
    *     websearch_to_tsquery('english', ?query?) @@
    *       (setweight(to_tsvector('english', n.title),   'A') ||
    *        setweight(to_tsvector('english', n.doctext), 'B'))
    &   AND n.id < ?before?
    &   AND n.id > ?after?
    &   AND ARRAY[s.id] <@ ?@sections_in?
    &   AND NOT ARRAY[s.id] <@ ?@sections_not_in?
    *   ORDER BY
    *       n.id ?sql_ord?
    *   LIMIT ?limit?
    SQL
    my ( $sql, @params ) = DBIx::PreQL->build_query(
        query       => $template,
        data        => \%data,
    );
    my $results = $self->pg->db->query( $sql, @params )->hashes->to_array;
    $self->log->trace("Search results: " . dump($results));
    return $results;
}