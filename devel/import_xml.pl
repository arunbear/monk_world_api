#!/usr/bin/env perl
use v5.40;
use autodie;
use Data::Dump 'dump';
use Getopt::Long;
use HTTP::Status qw(HTTP_CONFLICT);
use Mojo::DOM;
use Mojo::Util qw(trim);
use XXX -with => 'Data::Dump';
use Mojo::UserAgent;
use MonkWorld::API::Pg;
use MonkWorld::API::Request;

my %OPT = (
    uri       => 'http://localhost:3000',
    resume    => false,
    verbose   => false,
);
GetOptions(\%OPT,
    'uri=s',
    'resume',
    'verbose',
    'limit=i'
) or die "Error in command line arguments\n";

process_xml();

sub process_xml {
    my $files = get_input_for_parsing();
    my $count = 0;

    foreach my $file (@$files) {
        if (already_imported($file)) {
            warn "[Skipping] Already imported node: $file" if $OPT{verbose};
            next;
        }
        if ($OPT{resume} && (my $res = is_before_last_imported_node($file))) {
            warn $res if $OPT{verbose};
            next;
        }
        try {
            my $node_date = parse_xml($file);
            $count += import_node_data($node_date);
        }
        catch ($error) {
            if ($error =~ /\[Skipping/) {
                warn "$error, importing $file";
            }
            else {
                die "[STOPPED] $error, importing $file";
            }
        }
        last if defined $OPT{limit} && $count == $OPT{limit};
    }
    say "Nodes imported: $count";
}

sub parse_xml ($xml_file) {
    # Read and parse XML
    my $xml = Mojo::File->new($xml_file)->slurp;
    my $dom = Mojo::DOM->new($xml);

    # Extract node data
    my $node = $dom->at('node')
        or die "[Skipping] No node found in XML file $xml_file";

    my %field;
    $field{node_id} = $node->attr('id')
        or die "[Skipping] Node ID is required: $xml_file";

    for my $attr (qw(title created updated)) {
        $field{$attr} = $node->attr($attr);
    }

    # Extract node type
    my $type = $node->at('type');
    $field{type_name} = trim($type->text);
    $field{type_id}   = $type->attr('id');

    # Extract author
    my $author = $node->at('author');
    $field{author_id}       = $author->attr('id');
    $field{author_username} = trim($author->text);

    if (my $data = $node->at('data')) {
        for my $name (qw(doctext reputation root_node parent_node)) {
            if (my $field_elem = $data->at(qq{field[name="$name"]})) {
                $field{$name} = trim($field_elem->text // '');
            }
        }
    }

    $field{input_file} = $xml_file;

    return \%field;
}

sub import_node_data ($node_data) {
    return import_node_data_via_api($node_data);
}

# ====== Utility Functions ======

sub already_imported ($file) {
    # Extract node ID from filename (assuming format like '12345.xml')
    my ($node_id) = $file =~ m{([0-9]+)\.xml$}i
        or die "[Skipping] Could not extract node ID from filename: $file";

    return node_exists($node_id);
}

sub node_exists ($node_id) {
    my $pg = get_db_connection();
    my $db = $pg->db;
    my $result = $db->select('node', ['id'], { id => $node_id });
    return defined $result->hash;
}

# Check if a file's node ID is before the last imported node
# Returns true if the file should be skipped during resume
sub is_before_last_imported_node ($file) {
    my ($file_node_id) = $file =~ m/(\d+)\.xml$/i or return false;
    my $max_id = get_max_node_id();

    if ($file_node_id <= $max_id) {
        my $msg = "[Skipping] Node ID $file_node_id is lower than max node ID $max_id";
        return $msg;
    }
    return false;
}

sub get_max_node_id {
    my $pg = get_db_connection();
    my $db = $pg->db;
    my $result = $db->query('SELECT COALESCE(MAX(id), 0) AS max_id FROM node');
    return $result->hash->{max_id};
}

sub get_input_for_parsing {
    my $file = shift @ARGV
        or die "Error: No XML file or directory specified\n";

    if (-d $file) {
        chdir $file;
        no warnings 'numeric';
        return [sort { $a <=> $b } glob('*.xml')]; # get earliest nodes first
    }
    elsif (-f $file) {
        die "Error: Cannot read file '$file'\n" unless -r $file;
        return [$file];
    }
}

sub get_db_connection {
    state $pg = MonkWorld::API::Pg::get_pg();
    return $pg;
}

sub import_node_data_via_api ($node_data) {
    my $rows = 0;
    ensure_node_type_exists_api($node_data);
    ensure_author_exists_api($node_data);
    $rows = insert_node_api($node_data);
    return $rows;
}

sub ensure_node_type_exists_api ($node_data) {
    my $sitemap = get_sitemap();
    my $req = MonkWorld::API::Request
        ->new(
            link_meta => $sitemap->{_links}{create_node_type},
            server    => api_base_uri(),
        )
        ->update_json_entries(
            id   => $node_data->{type_id},
            name => $node_data->{type_name},
        );

    my $tx = api_ua()->build_tx($req->tx_args);
    my $res = api_ua()->start($tx)->result;

    return 1 if $res->is_success;
    return 1 if $res->code && $res->code == HTTP_CONFLICT; # already exists
    die "create node-type failed: " . ($res->message // $res->to_string);
}

sub ensure_author_exists_api ($node_data) {
    my $sitemap = get_sitemap();
    my $req = MonkWorld::API::Request
        ->new(
            link_meta => $sitemap->{_links}{create_monk},
            server => api_base_uri(),
        )
        ->update_json_entries(
            id       => $node_data->{author_id},
            username => $node_data->{author_username},
        );

    my $tx = api_ua()->build_tx($req->tx_args);
    my $res = api_ua()->start($tx)->result;

    return 1 if $res->is_success;
    return 1 if $res->code && $res->code == HTTP_CONFLICT; # already exists
    die "create monk failed: " . ($res->message // $res->to_string);
}

sub insert_node_api ($node_data) {
    return 0 if !$node_data->{doctext};
    $node_data->{updated} = $node_data->{created}
        if ($node_data->{updated} // '') eq '0000-00-00 00:00:00';

    my $sitemap = get_sitemap();
    my $req = MonkWorld::API::Request
        ->new(
            link_meta => $sitemap->{_links}{create_node},
            server => api_base_uri()
        )
        ->update_json_entries(
            node_id      => $node_data->{node_id},
            node_type_id => $node_data->{type_id},
            author_id    => $node_data->{author_id},
            title        => $node_data->{title},
            doctext      => $node_data->{doctext},
            created      => $node_data->{created},
            updated      => $node_data->{updated},
            (($node_data->{type_id} == 11) ? (
                root_node   => $node_data->{root_node},
                parent_node => $node_data->{parent_node}
            ) : ())
        );

    my $tx = api_ua()->build_tx($req->tx_args);
    my $res = api_ua()->start($tx)->result;
    if ($res->is_success) {
        say "Imported: $node_data->{node_id}";
        return 1;
    }
    my $err = eval { $res->json('/error') } // $res->body;
    if ($res->code == HTTP_CONFLICT
        || $err =~ /parent_node.+ is not present/
        || $err =~ /root_node.+ is not present/
        || $err =~ /Non root parent \d+ not present/
    ) {
        my $dump = $OPT{verbose} ? dump($node_data) : '';
        warn "[Skipping] Failed to import node $node_data->{node_id}: $err\n$dump";
        return 0;
    }
    die "create node failed: $err";
}

sub get_sitemap {
    state $sitemap = do {
        my $res = api_ua()->get(api_base_uri())->result;
        $res->is_success or die "Failed to fetch sitemap: " . $res->message;
        $res->json;
    };
    return $sitemap;
}

sub api_ua {
    state $ua = do {
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # allow self-signed during devel
        $ua;
    };
    return $ua;
}

sub api_base_uri { return $OPT{uri} }
