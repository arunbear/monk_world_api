package MonkWorld::API::Model::Search;
use v5.40;
use Data::Dump 'dump';
use Mojo::Base 'MonkWorld::API::Model::Base', -signatures;
use Mojo::Util qw(trim);

sub search ($self, $query, %params) {
    my $limit = $params{limit} // 50;
    my $sort  = $params{sort} // 'down';

    my $rank  = $params{rank} // 'n';
    if ($rank eq 'y') {
        delete @params{qw[before after]}; # these don't make sense with rank
    }
    else {
        $rank = false;
    }
    my $after  = $params{after} // -1;
    my $before = $params{before};
    my $include_sections = $params{include_sections} // [];

    $self->log->debug("Searching for: $query with parameters: " . (dump %params));
    $query = trim($query);

    return [] unless $query;

    # Enforce maximum limit
    $limit = 50 if $limit > 50;

    # simplify paging in SQL query
    my $boundary = do {
        if ($sort eq 'down') {
            if (!defined $before) {
                # use a value larger than any existing node ID
                $before =
                    $self->pg->db->query('SELECT COALESCE(MAX(id), 0)::bigint as max_id FROM node')
                        ->hash
                        ->{max_id} + 1;
            }
            $before;
        }
        elsif ($sort eq 'up') {
            $after;
        }
    };

    # Use PostgreSQL full-text search with websearch_to_tsquery
    my $sql_cmp = $sort eq 'down' ? '<'    : '>';
    my $sql_ord = $sort eq 'down' ? 'DESC' : 'ASC';
    my $sql_incl_sections = '';
    if (@$include_sections) {
        $sql_incl_sections = sprintf q{AND s.id IN (%s)}, join(',' => ('?') x @$include_sections);
    }
    my $sql_rank = '';
    my @query_params = ($boundary, @$include_sections, $query, $limit);
    if ($rank) {
        splice @query_params, 1, 0, $query;
        $sql_rank = q{ts_rank(
                        setweight(to_tsvector('english', n.title), 'A') ||
                        setweight(to_tsvector('english', n.doctext), 'B'),
                        websearch_to_tsquery('english', ?)
                    ) DESC,};
    }

    my $results = $self->pg->db->query(<<~"SQL", @query_params)->hashes->to_array;
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
        WHERE n.id $sql_cmp ?
          $sql_incl_sections
          AND websearch_to_tsquery('english', ?) @@
              (setweight(to_tsvector('english', n.title), 'A') ||
               setweight(to_tsvector('english', n.doctext), 'B'))
        ORDER BY
            $sql_rank
            n.id $sql_ord
        LIMIT ?
    SQL

    $self->log->trace("Search results: " . dump($results));
    return $results;
}