package MonkWorld::API::Pg;

use v5.40;
use Mojo::Pg;
use Exporter 'import';

our @EXPORT_OK = qw(get_pg);

sub get_pg {
    for('MONKWORLD_PG_URL') {
        $ENV{$_} =~ /^postgresql:/
            or die "$_ is not set correctly";
        my $pg = Mojo::Pg->new($ENV{$_});
        return $pg;
    }
}