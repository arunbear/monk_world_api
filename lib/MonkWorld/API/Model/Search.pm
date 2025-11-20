package MonkWorld::API::Model::Search;
use v5.40;
use Data::Dump 'dump';
use Mojo::Base 'MonkWorld::API::Model::Base', -signatures;
use Mojo::JSON qw(encode_json decode_json);

sub search ($self, $query) {
    $self->log->debug("Searching for: $query");
    # Clean and prepare the search query
    $query =~ s/[^\w\s]//g;  # Remove special characters
    $query =~ s/\s+/ /g;      # Collapse multiple spaces
    $query =~ s/^\s+|\s+$//g; # Trim spaces

    return [] unless $query;

    # Use PostgreSQL full-text search with websearch_to_tsquery
    my $results = $self->pg->db->query(<<~'SQL', $query, $query)->hashes->to_array;
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
        WHERE websearch_to_tsquery('english', ?) @@
              (setweight(to_tsvector('english', n.doctext), 'A') ||
               setweight(to_tsvector('english', n.title), 'B'))
        ORDER BY
            ts_rank(
                setweight(to_tsvector('english', n.doctext), 'A') ||
                setweight(to_tsvector('english', n.title), 'B'),
                websearch_to_tsquery('english', ?)
            ) DESC,
            n.created_at DESC
    SQL

    $self->log->debug("Search results: " . dump($results));
    return $results;
}