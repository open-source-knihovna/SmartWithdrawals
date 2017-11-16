package Koha::Plugin::Com::RBitTechnology::SmartWithdrawals;

use Modern::Perl;
use base qw(Koha::Plugins::Base);
use Encode qw( decode );
use Text::CSV::Encoded;
use File::Temp;
use File::Basename qw( dirname );
use utf8;
use Koha::AuthorisedValueCategories;
use Koha::AuthorisedValues;
use Koha::ItemTypes;
use Koha::Libraries;

use Data::Dumper;

our $VERSION = "1.0.0";

our $metadata = {
    name            => 'Inteligentní odpisy a přesuny',
    author          => 'Radek Šiman',
    description     => 'Tento modul poskytuje nástroje pro efektivní vyhledávání jednotek vhodných k odpisu či přesunům.',
    date_authored   => '2017-11-15',
    date_updated    => '2017-11-15',
    minimum_version => '16.05',
    maximum_version => undef,
    version         => $VERSION
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub install() {
    my ( $self, $args ) = @_;

    my $table_predefs = $self->get_qualified_table_name('predefs');
    my $table = $self->get_qualified_table_name('predef_options');

    return  C4::Context->dbh->do( "
        CREATE TABLE IF NOT EXISTS $table_predefs (
            `predef_id` INT( 11 ) NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(80) NOT NULL,
            `description` TEXT DEFAULT NULL,
            `date_created` DATETIME NOT NULL,
            `last_modified` DATETIME NOT NULL,
            PRIMARY KEY(`predef_id`)
        ) ENGINE = INNODB DEFAULT CHARACTER SET = utf8 COLLATE = utf8_czech_ci;
        " ) && C4::Context->dbh->do( "
        CREATE TABLE IF NOT EXISTS $table (
            `predef_option_id` INT( 11 ) NOT NULL AUTO_INCREMENT,
            `predef_id` INT( 11 ) NOT NULL,
            `variable` VARCHAR(50) NOT NULL,
            `value` TEXT NOT NULL,
            PRIMARY KEY(`predef_option_id`),
            INDEX `fk_predef_options_idx` (`predef_id` ASC),
            CONSTRAINT `fk_predef_options`
            FOREIGN KEY (`predef_id`)
            REFERENCES `$table_predefs` (`predef_id`)
            ON DELETE CASCADE
            ON UPDATE CASCADE
        ) ENGINE = INNODB DEFAULT CHARACTER SET = utf8 COLLATE = utf8_czech_ci;
    " );
}

sub uninstall() {
    my ( $self, $args ) = @_;

    my $table_predefs = $self->get_qualified_table_name('predefs');
    my $table_options = $self->get_qualified_table_name('predef_options');

    return C4::Context->dbh->do("DROP TABLE $table_options") && C4::Context->dbh->do("DROP TABLE $table_predefs");
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'configure.tt' });

        # build categories list
        my @categories = Koha::AuthorisedValueCategories->search({ category_name => { -not_in => ['', 'branches', 'itemtypes', 'cn_source']}}, { order_by => ['category_name'] } );
        my @category_list = ('?');
        for my $category ( @categories ) {
            push( @category_list, $category->category_name );
        }

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            categories => \@category_list,
            ccode      => $self->retrieve_data('ccode'),
            acqsource  => $self->retrieve_data('acqsource'),
            location   => $self->retrieve_data('location'),
        );

        print $cgi->header(-type => 'text/html',
                           -charset => 'utf-8');
        print $template->output();
    }
    else {
        $self->store_data(
            {
                ccode     => scalar $cgi->param('ccode'),
                acqsource => scalar $cgi->param('acqsource'),
                location  => scalar $cgi->param('location'),
                last_configured_by => C4::Context->userenv->{'number'},
            }
        );

        $self->go_home();
    }
}

sub tool {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('phase') ) {;
        $self->tool_list_predefs();
    }
    elsif ( $cgi->param('phase') eq 'edit' ) {
        $self->tool_edit_predef();
    }
    elsif ( $cgi->param('phase') eq 'run' ) {
        $self->tool_get_results();
    }
    elsif ( $cgi->param('phase') eq 'delete' ) {
        $self->tool_delete_predef();
    }
    elsif ( $cgi->param('phase') eq 'duplicate' ) {
        $self->tool_duplicate_predef();
    }
    elsif ( $cgi->param('phase') eq 'export' ) {
        $self->tool_export_results();
    }
}

sub tool_list_predefs {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'tool-list.tt' });

    print $cgi->header(-type => 'text/html',
                       -charset => 'utf-8');

    my $dbh = C4::Context->dbh;
    my $table_predefs = $self->get_qualified_table_name('predefs');

    my $query = "SELECT predef_id, name, description, date_created, last_modified FROM $table_predefs;";

    my $sth = $dbh->prepare($query);
    $sth->execute();

    my @results;
    while ( my $row = $sth->fetchrow_hashref() ) {
        push( @results, $row );
    }

    $template->param(
        predefs => \@results,
    );

    print $template->output();
}

sub tool_edit_predef {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'tool-edit.tt' });

    print $cgi->header(-type => 'text/html',
                       -charset => 'utf-8');

    my $options = {};
    my $predef = undef;
    if ( defined $cgi->param('predef') ) {
        my $dbh = C4::Context->dbh;
        my $table_options = $self->get_qualified_table_name('predef_options');
        my $table_predefs = $self->get_qualified_table_name('predefs');

        my $query = "SELECT predef_id, name, description FROM $table_predefs WHERE predef_id = ?;";
        my $sth = $dbh->prepare($query);
        $sth->execute( scalar $cgi->param('predef') );
        $predef = $sth->fetchrow_hashref();

        $query = "SELECT variable, value FROM $table_options WHERE predef_id = ?;";
        $sth = $dbh->prepare($query);
        $sth->execute( scalar $cgi->param('predef') );

        my %multi = map { $_ => 1 } qw(
            acqsource
            branches
            locations
            ccodes
        );

        while ( my $row = $sth->fetchrow_hashref() ) {
            if ( exists( $multi{$row->{variable}} ) ) {
                my @arr = split /,/, $row->{value};
                $options->{$row->{variable}} = \@arr;
            }
            else {
                $options->{$row->{variable}} = $row->{value};
            }
        }
    }

    # prepare item types
    my @itemtypes = Koha::ItemTypes->search({}, { order_by => ['description'], columns => [qw/itemtype description/] } );
    my @branches  = Koha::Libraries->search({}, { order_by => ['branchname'], columns => [qw/branchcode branchname/] } );
    my @locations = Koha::AuthorisedValues->search({ category => $self->retrieve_data('location')},  { order_by => ['lib'], columns => [qw/authorised_value lib/] } );
    my @ccodes    = Koha::AuthorisedValues->search({ category => $self->retrieve_data('ccode')},     { order_by => ['lib'], columns => [qw/authorised_value lib/] } );
    my @acqsource = Koha::AuthorisedValues->search({ category => $self->retrieve_data('acqsource')}, { order_by => ['lib'], columns => [qw/authorised_value lib/] } );
    $template->param(
        itemtypes => \@itemtypes,
        branches => \@branches,
        locations => \@locations,
        ccodes => \@ccodes,
        acqsource => \@acqsource,
        options => $options,
        predef => $predef,
    );

    print $template->output();
}

sub execute_sql {
    my ( $self, $predefId ) = @_;

        # retrieve column list
        my $dbh = C4::Context->dbh;
        my $table_options = $self->get_qualified_table_name('predef_options');
        my $query = "SELECT SUBSTRING(variable, 5) as colname FROM $table_options WHERE variable LIKE 'col_%' AND value = '1' AND predef_id = ?;";
        my $sth = $dbh->prepare($query);
        $sth->execute($predefId);

        my @columns;
        my @queryCols;
        while ( my $row = $sth->fetchrow_hashref() ) {
            push( @columns, $row->{colname} );

            push( @queryCols, 'barcode')                                if ( $row->{colname} eq 'barcode' );
            push( @queryCols, 'title')                                  if ( $row->{colname} eq 'title' );
            push( @queryCols, 'author')                                 if ( $row->{colname} eq 'author' );
            push( @queryCols, 'itemtypes.description as itemtype')      if ( $row->{colname} eq 'author' );
            push( @queryCols, 'itemcallnumber')                         if ( $row->{colname} eq 'callnumber' );
            push( @queryCols, 'stocknumber')                            if ( $row->{colname} eq 'stocknumber' );
            push( @queryCols, 'branches.branchname as holdingbranch')   if ( $row->{colname} eq 'holdingbranch' );
            push( @queryCols, 'replacementprice')                       if ( $row->{colname} eq 'replacementprice' );
        }

        # detect enabled subconditions
        my $enabled = {};
        $query = "SELECT SUBSTRING(variable, 5) as subcond FROM $table_options WHERE variable LIKE 'chk_%' AND value = '1' AND predef_id = ?;";
        $sth = $dbh->prepare($query);
        $sth->execute($predefId);
        while ( my $row = $sth->fetchrow_hashref() ) {
            $enabled->{$row->{subcond}} = 1;
        }

        # prepare subconditions
        my $subcond = {};
        $query = "SELECT variable, value FROM $table_options WHERE variable NOT LIKE 'col_%' AND variable NOT LIKE 'chk_%' AND predef_id = ?;";
        $sth = $dbh->prepare($query);
        $sth->execute($predefId);
        while ( my $row = $sth->fetchrow_hashref() ) {
            $subcond->{$row->{variable}} = $row->{value};
        }
        my $limit;
        my @where;
        my @bindParams;
        my @havingParts;
        my $period = {
            day => 1,
            month => 30,
            year => 365
        };

        if ( defined $subcond->{limit} ) {
            $limit = (" LIMIT " . $subcond->{limit});
        }

        # SELECT parts must be processed before any WHERE params to keep the right order of bindParams
        if ( $enabled->{available_items} ) {
            push( @havingParts, " pocet >= " . $subcond->{available_items} );
            push( @queryCols, '(select count(itemnumber) from items i where i.biblionumber = biblio.biblionumber) as pocet' );
        }
        if ( $enabled->{issues_max} ) {
            push( @queryCols, '(SELECT count(issue_id) FROM issues i WHERE i.itemnumber = items.itemnumber AND datediff(now(), issuedate) / ? <= ?) AS issues_count' );
            push( @queryCols, '(SELECT count(issue_id) FROM old_issues i WHERE i.itemnumber = items.itemnumber AND datediff(now(), issuedate) / ? <= ?) AS old_issues_count');
            push( @havingParts, 'issues_count + old_issues_count <= ' . $subcond->{issues_max} );
            push( @bindParams, $period->{$subcond->{issues_max_period_type}} );
            push( @bindParams, $subcond->{issues_max_period_length} );
            push( @bindParams, $period->{$subcond->{issues_max_period_type}} );
            push( @bindParams, $subcond->{issues_max_period_length} );
        }
        if ( $enabled->{reserves_max} ) {
            push( @queryCols, '(SELECT count(reserve_id) FROM reserves r WHERE r.biblionumber = items.biblionumber AND datediff(now(), reservedate) / ? <= ?) AS reserves_count' );
            push( @queryCols, '(SELECT count(reserve_id) FROM old_reserves r WHERE r.biblionumber = items.biblionumber AND datediff(now(), reservedate) / ? <= ?) AS old_reserves_count');
            push( @havingParts, 'reserves_count + old_reserves_count <= ' . $subcond->{reserves_max} );
            push( @bindParams, $period->{$subcond->{reserves_max_period_type}} );
            push( @bindParams, $subcond->{reserves_max_period_length} );
        }
        if ( $enabled->{last_reserve} ) {
            push( @queryCols, '(SELECT 1 AS last_reserve FROM reserves r WHERE r.biblionumber = items.biblionumber AND datediff(now(), reservedate) / ? <= ? LIMIT 1) as last_reserve' );
            push( @queryCols, '(SELECT 1 AS last_reserve FROM old_reserves r WHERE r.biblionumber = items.biblionumber AND datediff(now(), reservedate) / ? <= ? LIMIT 1) as last_old_reserve' );
            push( @havingParts, '(last_reserve IS NOT NULL OR last_old_reserve IS NOT NULL)' );
            push( @bindParams, $period->{$subcond->{last_reserve_period_type}} );
            push( @bindParams, $subcond->{last_reserve_period_length} );
            push( @bindParams, $period->{$subcond->{last_reserve_period_type}} );
            push( @bindParams, $subcond->{last_reserve_period_length} );
        }

        # WHERE must be processed after SELECT parts to keep the right order of bindParams
        if ( $enabled->{itype} ) {
            push( @where, "items.itype = ?" );
            push( @bindParams, $subcond->{itype} );
        }
        if ( $enabled->{item_price} ) {
            push( @where, "items.replacementprice <= ?" );
            push( @bindParams, $subcond->{item_price} );
        }
        if ( $enabled->{damage} ) {
            my $op = $subcond->{damage} == 0 ? '=' : '!=';
            push( @where, "items.damaged $op ?" );
            push( @bindParams, 0 );
        }
        if ( $enabled->{acqsource} ) {
            my @sources = split(',', $subcond->{acqsource});
            my @qMarks;
            foreach my $src ( @sources ) {
                push( @bindParams, $src );
                push( @qMarks, '?' );
            }
            push( @where, "items.booksellerid IN (" . join(',', @qMarks) . ")" );
        }
        if ( $enabled->{branches} ) {
            my @branches = split(',', $subcond->{branches});
            my @qMarks;
            foreach my $branch ( @branches ) {
                push( @bindParams, $branch );
                push( @qMarks, '?' );
            }
            push( @where, "items.holdingbranch IN (" . join(',', @qMarks) . ")" );
        }
        if ( $enabled->{locations} ) {
            my @locations = split(',', $subcond->{locations});
            my @qMarks;
            foreach my $loc ( @locations ) {
                push( @bindParams, $loc );
                push( @qMarks, '?' );
            }
            push( @where, "items.location IN (" . join(',', @qMarks) . ")" );
        }
        if ( $enabled->{ccodes} ) {
            my @ccodes = split(',', $subcond->{ccodes});
            my @qMarks;
            foreach my $ccode ( @ccodes ) {
                push( @bindParams, $ccode );
                push( @qMarks, '?' );
            }
            push( @where, "items.ccode IN (" . join(',', @qMarks) . ")" );
        }
        if ( $enabled->{last_issue} ) {
            push( @where, "DATEDIFF(now(), items.datelastborrowed) / ? <= ?" );
            push( @bindParams, $period->{$subcond->{last_issue_period_type}} );
            push( @bindParams, $subcond->{last_issue_period_length} );
        }
        if ( $enabled->{last_seen} ) {
            push( @where, "DATEDIFF(now(), items.datelastseen) / ? <= ?" );
            push( @bindParams, $period->{$subcond->{last_seen_period_type}} );
            push( @bindParams, $subcond->{last_seen_period_length} );
        }
        if ( $enabled->{last_acq} ) {
            push( @where, "DATEDIFF(now(), items.dateaccessioned) / ? <= ?" );
            push( @bindParams, $period->{$subcond->{last_acq_period_type}} );
            push( @bindParams, $subcond->{last_acq_period_length} );
        }


        # retrieve results to display
        my $dbColumns = join(',', @queryCols);
        my $having = (scalar @havingParts > 0) ? "HAVING " . join(' AND ', @havingParts) : '';
        my $subconditions = join(' AND ', @where);
        if ( $subconditions ) {
            $subconditions = " AND $subconditions";
        }
        $query = "SELECT $dbColumns "
            . " FROM items "
            . "LEFT JOIN biblio USING(biblionumber) "
            . "LEFT JOIN itemtypes ON itemtypes.itemtype = items.itype "
            . "LEFT JOIN branches ON branches.branchcode = items.holdingbranch "
            . "WHERE withdrawn_on IS NULL $subconditions "
            . "$having "
            . "$limit;";
        $sth = $dbh->prepare( $query );
        for my $i (0 .. $#bindParams) {
            $sth->bind_param($i + 1, $bindParams[$i]);
        }
        $sth->execute();
#print "<pre>";
#print Dumper($enabled);
#print Dumper(\@bindParams);
#print "</pre>";
#print $query;exit;

    return ($sth, @columns);
}

sub tool_get_results {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    if ( defined $cgi->param('save') || defined $cgi->param('save_run') ) {
        $self->tool_save_predef();
    }

    if ( defined $cgi->param('save') ) {
        $self->tool_list_predefs();
    }
    else {
        my $template = $self->get_template({ file => 'tool-results.tt' });

        print $cgi->header(-type => 'text/html',
                           -charset => 'utf-8');

        my $predefId = $cgi->param('predef');

        my ($sth, @columns) = $self->execute_sql($predefId);

        my @results;
        while ( my $row = $sth->fetchrow_hashref() ) {
            push( @results, $row );
        }

        $template->param(
            columns => \@columns,
            results => \@results,
            rows => scalar @results,
            predef => $predefId
        );
#print Dumper(\@results);exit;
        print $template->output();
    }

}

sub tool_save_predef {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $dbh = C4::Context->dbh;
    my $table_predefs = $self->get_qualified_table_name('predefs');
    my $table_options = $self->get_qualified_table_name('predef_options');

    my $predef_id;
    my $query;
    my $sth;

    if ( defined $cgi->param('predef') ) {
        $query = "UPDATE $table_predefs SET name = ?, description = ?, last_modified = now() WHERE predef_id = ?;";

        $predef_id = scalar $cgi->param('predef');

        $sth = $dbh->prepare($query);
        $sth->execute(
            defined $cgi->param('predef-name') ? scalar $cgi->param('predef-name') : '(nepojmenováno)',
            defined $cgi->param('predef-descr') ? scalar $cgi->param('predef-descr') : undef,
            $predef_id
        );

        $query = "DELETE FROM $table_options WHERE predef_id = ?;";
        $sth = $dbh->prepare($query);
        $sth->execute($predef_id);
    }
    else {
        $query = "INSERT INTO $table_predefs (name, description, date_created, last_modified) VALUES(?, ?, now(), now());";

        $sth = $dbh->prepare($query);
        $sth->execute(
            defined $cgi->param('predef-name') ? scalar $cgi->param('predef-name') : '(nepojmenováno)',
            defined $cgi->param('predef-descr') ? scalar $cgi->param('predef-descr') : undef
        );

        $predef_id = $dbh->last_insert_id(undef, undef, $table_predefs, 'predef_id');
    }


    my @fields = qw(
        limit
        chk_itype itype
        chk_available_items available_items
        chk_item_price item_price
        chk_damage damage
        chk_issues_max issues_max issues_max_period_length issues_max_period_type
        chk_reserves_max reserves_max reserves_max_period_length reserves_max_period_type
        chk_acqsource acqsource
        chk_branches branches
        chk_locations locations
        chk_ccodes ccodes
        chk_last_issue last_issue_period_length last_issue_period_type
        chk_last_seen last_seen_period_length last_seen_period_type
        chk_last_reserve last_reserve_period_length last_reserve_period_type
        chk_last_acq last_acq_period_length last_acq_period_type

        col_barcode
        col_title
        col_author
        col_itype
        col_callnumber
        col_stocknumber
        col_holdingbranch
        col_replacementprice
    );
    my %multi = map { $_ => 1 } qw(
        acqsource
        branches
        locations
        ccodes
    );

    my @data;
    for my $f (@fields) {
        if ( defined $cgi->param($f) ) {
            my $value;
            if ( exists( $multi{$f} ) ) {
                my @options = $cgi->multi_param($f);
                $value = join(',', @options);
            }
            else {
                $value = scalar $cgi->param($f);
            }
            push( @data, ($predef_id, $f, $value) );
        }
    }

    $query = "INSERT INTO $table_options (predef_id, variable, value) VALUES ";
    $query .= "(?, ?, ?)," x (scalar @data / 3);
    $query =~ s/,$/;/g;

    $sth = $dbh->prepare($query);
    $sth->execute( @data );
}

sub tool_delete_predef {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    if ( defined $cgi->param('predef') ) {
        my $dbh = C4::Context->dbh;
        my $table_predefs = $self->get_qualified_table_name('predefs');

        my $query = "DELETE FROM $table_predefs WHERE predef_id = ?;";

        my $sth = $dbh->prepare($query);
        $sth->execute( scalar $cgi->param('predef') );
    }

    $self->tool_list_predefs();
}

sub tool_duplicate_predef {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    if ( defined $cgi->param('predef') ) {
        my $dbh = C4::Context->dbh;
        my $table_predefs = $self->get_qualified_table_name('predefs');
        my $table_options = $self->get_qualified_table_name('predef_options');

        my $query = "INSERT INTO $table_predefs (name, description, date_created, last_modified) SELECT CONCAT('(kopie ', ? ') ', name), description, now(), now() FROM $table_predefs WHERE predef_id = ?;";
        my $sth = $dbh->prepare($query);
        $sth->execute( $cgi->param('predef'), $cgi->param('predef') );
        my $new_predef_id = $dbh->last_insert_id(undef, undef, $table_predefs, 'predef_id');

        $query = "INSERT INTO $table_options (predef_id, variable, value) SELECT ?, variable, value FROM $table_options WHERE predef_id = ?;";
        $sth = $dbh->prepare($query);
        $sth->execute( $new_predef_id, $cgi->param('predef') );
    }

    $self->tool_list_predefs();
}

# pass $sth, get back an array of names for the column headers
sub header_cell_values {
    my $sth = shift or return ();
    return '' unless ($sth->{NAME});
    my @dbHeaders = @{$sth->{NAME}};
    my @headers;

    foreach my $hdr (@dbHeaders) {
        push( @headers, 'Čárový kód' )          if ( $hdr eq 'barcode' );
        push( @headers, 'Název titulu' )        if ( $hdr eq 'title' );
        push( @headers, 'Autor' )               if ( $hdr eq 'author' );
        push( @headers, 'Typ jednotky' )        if ( $hdr eq 'itemtype' );
        push( @headers, 'Signatura' )           if ( $hdr eq 'itemcallnumber' );
        push( @headers, 'Přírůstkové č.' )      if ( $hdr eq 'stocknumber' );
        push( @headers, 'Aktuální umístění' )   if ( $hdr eq 'holdingbranch' );
        push( @headers, 'Nákupní cena' )        if ( $hdr eq 'replacementprice' );
    }
    return @headers;
}

sub tool_export_results {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    my $format = $cgi->param('format');

    my ($sth, @columns) = $self->execute_sql(scalar $cgi->param('predef'));
    my ( $type, $content );

    if ($format eq 'tab') {
        $type = 'application/octet-stream';
        $content .= join("\t", header_cell_values($sth)) . "\n";
        #$content = Encode::decode('UTF-8', $content);
        while (my $row = $sth->fetchrow_arrayref()) {
            $content .= join("\t", @$row) . "\n";
        }
    }
    elsif ( $format eq 'csv' ) {
        my $delimiter = C4::Context->preference('delimiter') || ',';
        $delimiter = "\t" if $delimiter eq 'tabulation';
        $type = 'application/csv';
        my $csv = Text::CSV::Encoded->new({ encoding_out => 'UTF-8', sep_char => $delimiter});
        $csv or die "Text::CSV::Encoded->new({binary => 1}) FAILED: " . Text::CSV::Encoded->error_diag();
        if ($csv->combine(header_cell_values($sth))) {
            $content .= Encode::decode('UTF-8', $csv->string()) . "\n";
        }
        while (my $row = $sth->fetchrow_arrayref()) {
            if ($csv->combine(@$row)) {
                $content .= $csv->string() . "\n";
            }
        }
    }
    elsif ( $format eq 'ods' ) {
        $type = 'application/vnd.oasis.opendocument.spreadsheet';
        my $ods_fh = File::Temp->new( UNLINK => 0 );
        my $ods_filepath = $ods_fh->filename;

        use OpenOffice::OODoc;
        my $tmpdir = dirname $ods_filepath;
        odfWorkingDirectory( $tmpdir );
        my $container = odfContainer( $ods_filepath, create => 'spreadsheet' );
        my $doc = odfDocument (
            container => $container,
            part      => 'content'
        );
        my $table = $doc->getTable(0);
        my @headers = header_cell_values( $sth );
        my $rows = $sth->fetchall_arrayref();
        my ( $nb_rows, $nb_cols ) = ( 0, 0 );
        $nb_rows = @$rows;
        $nb_cols = @headers;
        $doc->expandTable( $table, $nb_rows + 1, $nb_cols );

        my $row = $doc->getRow( $table, 0 );
        my $j = 0;
        for my $header ( @headers ) {
            my $value = Encode::encode( 'UTF8', $header );
            $doc->cellValue( $row, $j, $value );
            $j++;
        }
        my $i = 1;
        for ( @$rows ) {
            $row = $doc->getRow( $table, $i );
            for ( my $j = 0 ; $j < $nb_cols ; $j++ ) {
                my $value = Encode::encode( 'UTF8', $rows->[$i - 1][$j] );
                $doc->cellValue( $row, $j, $value );
            }
            $i++;
        }
        $doc->save();
        binmode(STDOUT);
        open $ods_fh, '<', $ods_filepath;
        $content .= $_ while <$ods_fh>;
        unlink $ods_filepath;
    }

    print $cgi->header(
        -type => $type,
        -attachment=> 'odpisy.' . $format
    );
    print $content;

    exit;
}

1;
