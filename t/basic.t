use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use HTTP::Status;

my $t = Test::Mojo->new('MonkWorld::API');
$t->get_ok('/health')->status_is(HTTP::Status::HTTP_OK);

done_testing();
