package MonkWorld::API::Model::Search;
use v5.40;
use Data::Dump 'dump';
use Mojo::Base 'MonkWorld::API::Model::Base', -signatures;
use Mojo::Util qw(trim);

sub search ($self, $query, %params) {
    my $limit = $params{limit} // 50;
    my $after = $params{after};
    my $before = $params{before};
    my $dir = $params{dir} // 'down';

    $self->log->debug("Searching for: $query with parameters: " . (dump %params));
    $query = trim($query);

    return [] unless $query;

    # Enforce maximum limit
    $limit = 50 if $limit > 50;

    if ($dir eq 'down' && !defined $before) {
        # Get the maximum node ID if before is not provided
        $before = $self->pg->db->query('SELECT COALESCE(MAX(id), 0)::bigint as max_id FROM node')
                      ->hash
                      ->{max_id} + 1;
    }

    # Use PostgreSQL full-text search with websearch_to_tsquery
    my $sql_dir = $dir eq 'down' ? '<' : '>';
    my $sql_ord = $dir eq 'down' ? 'DESC' : 'ASC';
    my $boundary = $dir eq 'down' ? $after : -1;
    my $results = $self->pg->db->query(<<~"SQL", $before, $query, $query, $limit)->hashes->to_array;
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
        WHERE n.id $sql_dir ?
          AND websearch_to_tsquery('english', ?) @@
              (setweight(to_tsvector('english', n.title), 'A') ||
               setweight(to_tsvector('english', n.doctext), 'B'))
        ORDER BY
            n.id $sql_ord,
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