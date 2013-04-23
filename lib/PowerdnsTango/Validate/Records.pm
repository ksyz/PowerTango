package PowerdnsTango::Validate::Records;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Data::Validate::Domain qw(is_domain);
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use Scalar::Util qw(looks_like_number);
use Email::Valid;
use DateTime;

use base "Exporter";

our @EXPORT  = qw(check_soa check_record calc_serial check_valid_masters);
our $VERSION = '0.2';

sub check_soa
{
    my ($name_server, $contact, $refresh, $retry, $expire, $minimum, $ttl) = @_;
    my $soa_email = soa_email_regex();
    my $stat      = 1;
    my $message   = "ok";
	my $conf = config->{dns};

    if (!defined $name_server || !is_domain($name_server))
    {
        $message = "a name server must be a valid domain";
    }
    elsif (!defined $contact || $contact !~ m{ $soa_email }xmsi)
    {
        $message =
          "$contact does not appear to be a valid SOA contact (see: rfc 1912).";
    }
    elsif (   !defined $refresh
           || !looks_like_number($refresh)
           || $refresh < $conf->{soa_refresh_min}
           || $refresh > $conf->{soa_refresh_max})
    {
        $message = "REFRESH must be a number between $conf->{soa_refresh_min} and $conf->{soa_refresh_max}";
    }
    elsif (   !defined $retry
           || !looks_like_number($retry)
           || $retry < $conf->{soa_retry_min}
           || $retry > $conf->{soa_retry_max})
    {
        $message = "RETRY must be a number between $conf->{soa_retry_min} and $conf->{soa_retry_max}";
    }
    elsif (   !defined $expire
           || !looks_like_number($expire)
           || $expire < $conf->{soa_expire_min}
           || $expire > $conf->{soa_expire_max})
    {
        $message = "EXPIRE must be a number between $conf->{soa_expire_min} and $conf->{soa_expire_max}";
    }
    elsif (   !defined $minimum
           || !looks_like_number($minimum)
           || $minimum < $conf->{soa_minimum_min}
           || $minimum > $conf->{soa_minimum_max})
    {
        $message = "MINIMUM must be a number between $conf->{soa_minimum_min} and $conf->{soa_minimum_max}";
    }
    elsif (!defined $ttl || !looks_like_number($ttl) || $ttl < $conf->{soa_ttl_min} || $ttl > $conf->{soa_ttl_max})
    {
        $message = "RR TTL must be a number between $conf->{soa_ttl_min} and $conf->{soa_ttl_max}";
    }
    else
    {
        $stat = 0;
    }

    return ($stat, $message);
}

sub check_record
{
    my ($name, $ttl, $type, $content, $prio, $record_type) = @_;
    my $stat    = 1;
    my $message = "ok";
    my $sth;
    my $count;
    my $default_ttl_minimum = database->quick_select('admin_settings_tango',
                                            {setting => 'default_ttl_minimum'});
    $default_ttl_minimum->{value} = 3600
      if (!defined $default_ttl_minimum->{value}
          || $default_ttl_minimum->{value} !~ m/^(\d)+$/);

    $record_type = 'live'
      if (!defined $record_type
          && ($record_type ne 'live' || $record_type ne 'template'));

    if ($record_type eq 'live' && ($content =~ m/%zone%/ || $name =~ m/%zone%/))
    {
        $message = "Use of %zone% is only allowed in templates";
    }
    elsif (   !defined $name
           || (!is_domain($name) && $type ne 'TXT')
           || ($name !~ m/(\w)+/))
    {
        $message = "Name is invalid";
    }
    elsif (!defined $content)
    {
        $message = "Content must have a value";
    }
    elsif (!defined $type)
    {
        $message = "Type must have a value";
    }
    elsif (   $type ne 'A'
           && $type ne 'AAAA'
           && $type ne 'CNAME'
           && $type ne 'LOC'
           && $type ne 'MX'
           && $type ne 'NS'
           && $type ne 'PTR'
           && $type ne 'SPF'
           && $type ne 'SRV'
           && $type ne 'TXT')
    {
        $message = "Type is unknown";
    }
    elsif (   !defined $ttl
           || $ttl !~ m/^(\d)+$/
           || $ttl < $default_ttl_minimum->{value})
    {
        $message =
          "TTL must be a number equal or greater than $default_ttl_minimum->{value}";
    }
    elsif ($type eq 'A' && !is_ipv4($content))
    {
        $message = "A record must be a valid ipv4 address";
    }
    elsif ($type eq 'AAAA' && !is_ipv6($content))
    {
        $message = "AAAA record must be a valid ipv6 address";
    }
    elsif ($type eq 'CNAME' && !is_domain($content) && $content !~ m/%zone%$/)
    {
        $message =
          "CNAME record must be unique and contain a valid domain name";
    }
    elsif ($type eq 'LOC' && $content !~ m/(\w)+/)
    {
        $message = "LOC record must contain a geographical location";
    }
    elsif (
           $type eq 'MX'
           && (   !defined $prio
               || $prio !~ m/^(\d)+$/
               || $prio < 1
               || $prio >= 65535
               || (!is_domain($content) && $content !~ m/%zone%$/))
          )
    {
        $message =
          "MX record must have a priority number and contain a valid domain name";
    }
    elsif ($type eq 'NS' && !is_domain($content))
    {
        $message = "NS record must contain a valid domain name";
    }
    elsif ($type eq 'PTR' && (!is_ipv4($content) && !is_ipv6($content)))
    {
        $message = "PTR record must be a valid ip address";
    }
    elsif ($type eq 'SPF' && $content !~ m/(\w)+/)
    {
        $message = "SPF record must contain alphanumeric characters";
    }
    elsif (
           $type eq 'SRV'
           && (   !defined $prio
               || $prio !~ m/^(\d)+$/
               || $prio < 1
               || $prio >= 65535
               || $content !~ m/(\w)+/)
          )
    {
        $message =
          "SRV record must have a priority number and contain a alphanumeric characters";
    }
    elsif ($type eq 'TXT' && $content !~ m/(\w)+/)
    {
        $message = "TXT record must contain a alphanumeric characters";
    }
    else
    {
        $stat = 0;
    }

    return ($stat, $message);
}

sub calc_serial
{
    my $domain_old_serial = shift;

    my $dt = DateTime->now;
    my ($year, $month, $day) = split(/-/, $dt->ymd('-'));
    my $domain_serial = ($year . $month . $day . 0 . 1);

    for (my $i = 1 ; $domain_old_serial >= $domain_serial ; $i++)
    {
        if ($i >= 100)
        {
            # Can't go any higher in one day without breaking RFC
            return ($year . $month . $day . 99);
        }
        elsif ($i >= 10)
        {
            $domain_serial = ($year . $month . $day . $i);
        }
        else
        {
            $domain_serial = ($year . $month . $day . 0 . $i);
        }
    }

    return ($domain_serial);
}

sub soa_email_regex
{
    return qr/\b
                 (   
                    (?=[a-z0-9-]{1,63}\.)

                    (xn--)?[a-z0-9]+(-[a-z0-9]+)*\.

                 )  +[a-z]{2,63}

           \b/xmsi;
}

sub check_valid_masters {
    my $_masters = shift;
    my $masters;


    if (ref($_masters) eq "SCALAR") {
        $masters = ${$_masters};
    }
    else {
        $masters = $_masters;
    }

    return undef
        unless defined $masters;

    my @masters = split(/\s*,\s*/, $masters);

    return undef
        if (scalar @masters < 1);

    for (@masters) {
        return undef 
            if (!is_domain($_) && !is_ipv4($_) && !is_ipv6($_));
    }

    if (!wantarray or ref($_masters)) {
        my $new_masters = join(',', @masters);

        $_masters = \$new_masters
            if (ref($_masters));

        return $new_masters;
    }
    else {
        return @masters;
    }
}

1;
