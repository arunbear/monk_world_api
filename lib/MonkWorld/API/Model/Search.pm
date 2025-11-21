package MonkWorld::API::Model::Search;
use v5.40;
use Data::Dump 'dump';
use Mojo::Base 'MonkWorld::API::Model::Base', -signatures;
use Mojo::Util qw(trim);

sub search ($self, $query, $limit = 50, $start = undef) {
    $self->log->debug("Searching for: $query with limit: $limit" . ($start ? " starting from: $start" : ''));
    $query = trim($query);

    return [] unless $query;

    # Enforce maximum limit
    $limit = 50 if $limit > 50;

    if (!defined $start) {
        $start = $self->pg->db->query('SELECT COALESCE(MAX(id), 0)::bigint as max_id FROM node')
                      ->hash
                      ->{max_id} + 1;
    }

    # Use PostgreSQL full-text search with websearch_to_tsquery
    my $results = $self->pg->db->query(<<~"SQL", $start, $query, $query, $limit)->hashes->to_array;
        SELECT
            n.id,
            n.title,
            n.created_at,
            m.id as author_id,
            m.username as author_username,
            s.name as section_name
        FROM node n
        JOIN monk m ON n.author_id = m.id
        JOIN node_type nt ON n.node_type_id = nt.id
        JOIN node r ON r.id = (subpath(n.path, 0, 1))::text::bigint
        JOIN node_type s ON s.id = r.node_type_id
        WHERE n.id < ?
          AND websearch_to_tsquery('english', ?) @@
              (setweight(to_tsvector('english', n.title), 'A') ||
               setweight(to_tsvector('english', n.doctext), 'B'))
        ORDER BY
            n.id DESC,
            ts_rank(
                setweight(to_tsvector('english', n.title), 'A') ||
                setweight(to_tsvector('english', n.doctext), 'B'),
                websearch_to_tsquery('english', ?)
            ) DESC
        LIMIT ?
    SQL

    $self->log->debug("Search results: " . dump($results));
    return $results;
}