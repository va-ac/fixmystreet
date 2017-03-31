
package FixMyStreet::SendReport::Cooperanet;

use Moo;
use FixMyStreet::Email;

BEGIN { extends 'FixMyStreet::SendReport'; }

my $Auxjp001= prepareTelegram();

sub build_recipient_list {
    my ( $self, $row, $h ) = @_;

    my $all_confirmed = 1;
    foreach my $body ( @{ $self->bodies } ) {

        my $contact = $row->result_source->schema->resultset("Contact")->find( {
            deleted => 0,
            body_id => $body->id,
            category => $row->category
        } );

        my ($body_email, $confirmed, $note) = ( $contact->email, $contact->confirmed, $contact->note );

        unless ($confirmed) {
            $all_confirmed = 0;
            $note = 'Body ' . $row->bodies_str . ' deleted'
                unless $note;
            $body_email = 'N/A' unless $body_email;
            $self->unconfirmed_counts->{$body_email}{$row->category}++;
            $self->unconfirmed_notes->{$body_email}{$row->category} = $note;
        }

        my $body_name = $body->name;
        # see something uses council areas but doesn't send to councils so just use a
        # generic name here to minimise confusion
        if ( $row->cobrand eq 'seesomething' ) {
            $body_name = 'See Something, Say Something';
        }

        my @emails;
        # allow multiple emails per contact
        if ( $body_email =~ /,/ ) {
            @emails = split(/,/, $body_email);
        } else {
            @emails = ( $body_email );
        }
        for my $email ( @emails ) {
            push @{ $self->to }, [ $email, $body_name ];
        }
    }

    return $all_confirmed && @{$self->to};
}

sub get_template {
    my ( $self, $row ) = @_;
    return 'submit.txt';
}

sub send_from {
    my ( $self, $row ) = @_;
    return [ $row->user->email, $row->name ];
}

sub send {
    my $self = shift;
    my ( $row, $h ) = @_;

    my $recips = $self->build_recipient_list( $row, $h );

    # on a staging server send emails to ourselves rather than the bodies
    if (FixMyStreet->staging_flag('send_reports', 0) && !FixMyStreet->test_mode) {
        $recips = 1;
        @{$self->to} = [ $row->user->email, $self->to->[0][1] || $row->name ];
    }
	
    unless ($recips) {
        $self->error( 'No recipients' );
        return 1;
    }

    my ($verbose, $nomail) = CronFns::options();
    my $cobrand = FixMyStreet::Cobrand->get_class_for_moniker($row->cobrand)->new();
    my $params = {
        To => $self->to,
        From => $self->send_from( $row ),
    };

    $cobrand->munge_sendreport_params($row, $h, $params) if $cobrand->can('munge_sendreport_params');

    $params->{Bcc} = $self->bcc if @{$self->bcc};

    my $sender = sprintf('<fms-%s@%s>',
        FixMyStreet::Email::generate_verp_token('report', $row->id),
        FixMyStreet->config('EMAIL_DOMAIN')
    );

    if (FixMyStreet::Email::test_dmarc($params->{From}[0])) {
        $params->{'Reply-To'} = [ $params->{From} ];
        $params->{From} = [ $sender, $params->{From}[1] ];
    }

    my $resulatdodelxml = $self->jadu_form_fields($row, $h);
    my $resuladtotelegram = prepareTelegram($resulatdodelxml);

    my $result = FixMyStreet::Email::send_cron($row->result_source->schema,
        $self->get_template($row), $h,
        $params, $sender, $nomail, $cobrand, $row->lang);
    


    unless ($result) {
        $self->success(1);
    } else {
        $self->error( 'Failed to send email' );
    } 

    return $result;
}

sub _get_district_for_contact {
    my ( $lat, $lon ) = @_;
    my $district =
      mySociety::MaPit::call( 'point', "4326/$lon,$lat", type => 'DIS' );
    ($district) = keys %$district;
    return $district;
}

sub prepareTelegram {

	my($telegrammsg) = @_;
	my $telegramres = sendTelegramMenus($telegrammsg,"-186927773");
	$telegramres = sendTelegramMenus($telegrammsg,"-157033401");
	$telegramres = sendTelegramMenus($telegrammsg,"-1001109127574");

   # print "el resultado fue: ".$telegramres;

    return $telegramres;

}

sub sendTelegramMenus{
    #usage
    #sendTelegram($telegramEndPoint,$textMessage,$chat_id,$replyMarkup)
    my(@values) = @_;
    my $telegramEndPoint = "https://api.telegram.org/bot207932100:AAHber1wFMgsFsXrJkHPe-e6NB7PO79voI4/sendMessage";
    my $textMessage = $values[0];
    my $chat_id = $values[1];

    $textMessage = "" unless $textMessage;
    
    my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
    my $completeUrl =  $telegramEndPoint.'?chat_id='.$chat_id.'&text='.$textMessage;
   # print "URL: ".$completeUrl."\n\n";
    my $response = $ua->get($completeUrl);
    my $content  = $response->decoded_content();
    my $resCode = $response->code();

   # print "RESPONSE CODE $resCode \n Content: $content\n\n";

    return($resCode);
}


sub jadu_form_fields {
    my ($self, $row, $h) = @_;
    my $xml = XML::Simple->new(
        NoAttr=> 1,
        KeepRoot => 1,
        SuppressEmpty => 0,
    );
    my $metas = $row->get_extra_fields();
    my %extras;
    foreach my $field (@$metas) {
        $extras{$field->{name}} = $field->{value};
    }
    my $Simpletext = "Hemos recibido una nueva notificacion en Cooperanet : \n".$h->{title}.": ".$h->{detail};
	$Simpletext = $Simpletext."\n es posible ver esta notificacion  en http://www.cooperanet.cl/report/".$h->{id};

    my $cobrand = FixMyStreet::Cobrand->get_class_for_moniker($row->cobrand)->new();
    my $output = $xml->XMLout({
        formfields => {
            formfield => [
                {
                    name => 'RequestTitle',
                    value => $h->{title}
                },
                {
                    name => 'RequestDetails',
                    value => $h->{detail}
                },
                {
                    name => 'ReporterName',
                    value => $h->{name}
                },
                {
                    name => 'ReporterEmail',
                    value => $h->{email}
                },
                {
                    name => 'ReporterAnonymity',
                    value => $row->anonymous ? 'True' : 'False'
                },
                {
                    name => 'ReportedDateTime',
                    value => $h->{confirmed}
                },
                {
                    name => 'Imageurl1',
                    value => $row->photos->[0] ? ($cobrand->base_url . $row->photos->[0]->{url_full}) : ''
                },
                {
                    name => 'Imageurl2',
                    value => $row->photos->[1] ? ($cobrand->base_url . $row->photos->[1]->{url_full}) : ''
                },
                {
                    name => 'Imageurl3',
                    value => $row->photos->[2] ? ($cobrand->base_url . $row->photos->[2]->{url_full}) : ''
                }
            ]
        }
    });
    # Si quieres una salida xml se debe salir con output y si quieres una salida con texto simple con Simpletext
    $output =~ s/>[\s\n]+</></g;
    return $Simpletext;
}

1;
