#!/usr/bin/perl

# Revealing the 'Master' versions of photos from Photos.app in Finder.
# 写真.app に登録されている写真の「マスター」を Finder に表示する.

use strict;
use warnings;
use utf8;

use DBI;
use File::Spec;
use File::Temp;
use File::Copy;
use File::HomeDir;
use Mac::Pasteboard;
use Mac::PropertyList;
use Encode;
use Encode::UTF8Mac;

my $photos_library_filename = '写真 Library.photoslibrary';
my $path_to_photos_library = File::HomeDir->my_pictures ? 
	File::Spec->catfile(File::HomeDir->my_pictures, $photos_library_filename) :
	File::Spec->catfile(File::HomeDir->my_home, 'Pictures', $photos_library_filename) ;

sub usage {
	print <<END;

No photo ids found in pasteboard.

1. Copy some photos in Photos.app.
2. Run this script.
3. The 'Master' versions of photos are revealed in Finder.

END
	exit 0;
}

main();

sub abort(@) {
	print @_, "\n";
	exit -1;
}

sub main {
	my @modelIds = version_modelIds_from_pasteboard();
	if (!@modelIds) {
		usage();
	}
	
	my $db_path = prepare_copy_of_photosdb();
	
	my @pathes = imagePathes_from_modelIds($db_path, @modelIds);
	
	foreach (@pathes) {
		reveal($_);
	}
	command('open', '-a', 'Finder');
}

sub reveal {
	my $path = shift;
	print Encode::encode('utf8', $path), "\n";
	if (-d $path) {
		command('open', '-a', 'Finder', $path);
	} elsif (-f $path) {
		command('osascript', '-e', qq{tell application "Finder" to reveal "$path" as POSIX file});
	}
}

sub command {
	system map { Encode::encode('utf-8-mac', $_) } @_;
}

sub version_modelIds_from_pasteboard {
	my $pb = Mac::Pasteboard->new();
	
	my @data = $pb->paste_all();
	
	foreach (@data) {
		if ($_->{data} && $_->{data} =~ /<plist/) {
			my $parsed = Mac::PropertyList::parse_plist($_->{data})->as_perl;
			return map { $_->{modelId} } @$parsed;
		}
	}
	
	return ();
}

sub prepare_copy_of_photosdb {
	my $dir = File::Temp::tempdir( CLEANUP => 1 );
	my $filename = 'photos.db';
	
	my $db_origin_path = File::Spec->catfile($path_to_photos_library, 'database', $filename);
	if (! -e $db_origin_path) {
		abort "photos.db not found at $db_origin_path";
	}
	
	my $db_copied_path = File::Spec->catfile($dir, $filename);
	File::Copy::copy($db_origin_path, $db_copied_path);
	if (! -e $db_copied_path) {
		abort "copying photos.db to temporary directory failed.";
	}
	
	return $db_copied_path;
}

sub imagePathes_from_modelIds {
	my $db_path = shift;
	my @ids = @_;
	
	my $sql = q{select RKMaster.imagePath from RKVersion inner join RKMaster on RKVersion.masterId=RKMaster.modelId where RKVersion.modelId IN (??);};
	$sql =~ s/\?\?/join ',', map {'?'} @_/e;
	
	my $dbh = DBI->connect("dbi:SQLite:dbname=$db_path","","");
	abort "connecting sqlite3 database $db_path failed." unless $dbh;
	my $sth = $dbh->prepare($sql);
	abort "prepareing sql $sql failed." unless $sth;
	$sth->execute(@ids);
	my @results = map {
		File::Spec->catfile($path_to_photos_library, 'Masters', $_->[0]);
	} @{ $sth->fetchall_arrayref };
	$dbh->disconnect;
	
	return @results;
}

__END__

## 写真.app からのコピーの内容
---
- data: |
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <array>
    	<dict>
    		<key>itemType</key>
    		<integer>1</integer>
    		<key>libraryUuid</key>
    		<string>OoOx6QFkS1a3lwJeHMGEjQ</string>
    		<key>modelId</key>
    		<integer>24761</integer>
    	</dict>
    </array>
    </plist>
  flags: 0
  flavor: dyn.ah62d4rv4gu8ywyc2nbu1g7dfqm10c6xekr1067dwr70g23pw
  id: 789514
- data: RVBB6Db9R7m4BB7rieDOUQ
  flags: 0
  flavor: com.apple.PhotoPrintProduct.photoUUID
  id: 789514
- data: file:///Users/hrk/Pictures/%E5%86%99%E7%9C%9F%20Library.photoslibrary/resources/proxies/derivatives/60/00/60b9/UNADJUSTEDNONRAW_thumb_60b9.jpg
  flags: 0
  flavor: public.file-url
  id: 1

# sqlite3 で 写真.app のデータベースを開く

$ mkdir temp; cd temp; cp path-to-photos-library-database/photos.db .
$ sqlite3 photos.db 

# スキーマを調べる

sqlite> .tables
RKMaster
RKVersion

sqlite> .schema RKMaster
CREATE TABLE RKMaster (modelId integer primary key autoincrement, uuid varchar, fingerprint varchar, orientation integer, name varchar, createDate timestamp, isInTrash integer, inTrashDate timestamp, cloudLibraryState integer, hasBeenSynced integer, fileVolumeUuid varchar, fileIsReference integer, isMissing integer, duration decimal, fileModificationDate timestamp, bookmarkId integer, volumeId integer, fileSize integer, width integer, height integer, UTI varchar, importGroupUuid varchar, alternateMasterUuid varchar, originalVersionName varchar, fileName varchar, isExternallyEditable integer, isTrulyRaw integer, hasAttachments integer, hasNotes integer, imagePath varchar, imageDate timestamp, fileCreationDate timestamp, originalFileName varchar, originalFileSize integer, importedBy integer, burstUuid varchar, importComplete integer, imageTimeZoneOffsetSeconds integer, streamAssetId varchar, photoStreamTagId varchar, isCloudQuarantined integer, mediaGroupId varchar, hasCheckedMediaGroupId integer, originatingAssetIdentifier varchar, groupingUuid varchar, cloudImportedBy integer);

sqlite> .schema RKVersion
CREATE TABLE RKVersion (modelId integer primary key autoincrement, uuid varchar, orientation integer, naturalDuration decimal, name varchar, createDate timestamp, isFavorite integer, isInTrash integer, inTrashDate timestamp, isHidden integer, colorLabelIndex integer, cloudLibraryState integer, hasBeenSynced integer, cloudIdentifier varchar, type integer, adjustmentUuid varchar, masterUuid varchar, fileName varchar, hasNotes integer, imageDate timestamp, burstUuid varchar, imageTimeZoneOffsetSeconds integer, reverseLocationData blob, reverseLocationDataIsValid integer, lastModifiedDate timestamp, versionNumber integer, masterId integer, rawMasterUuid varchar, nonRawMasterUuid varchar, projectUuid varchar, imageTimeZoneName varchar, mainRating integer, isFlagged integer, isOriginal integer, isEditable integer, masterHeight integer, masterWidth integer, processedHeight integer, processedWidth integer, rotation integer, hasAdjustments integer, thumbnailGroup varchar, overridePlaceId integer, latitude decimal, longitude decimal, exifLatitude decimal, exifLongitude decimal, renderVersion integer, supportedStatus integer, videoInPoint varchar, videoOutPoint varchar, videoPosterFramePoint varchar, showInLibrary integer, editState integer, contentVersion integer, propertiesVersion integer, faceDetectionState integer, faceDetectionIsFromPreview integer, faceDetectionRotationFromMaster integer, hasKeywords integer, subType integer, specialType integer, momentUuid varchar, burstPickType integer, extendedDescription varchar, outputUpToDate integer, previewsAdjustmentUuid varchar, pendingAdjustmentUuid varchar, faceAdjustmentUuid varchar, lastSharedDate timestamp, isCloudQuarantined integer, videoCpDurationValue integer, videoCpDurationTimescale integer, videoCpImageDisplayValue integer, videoCpImageDisplayTimescale integer, videoCpVisibilityState integer, colorSpaceValidationState integer, momentSortIdx integer, sceneAlgorithmVersion integer, sceneAdjustmentUuid varchar, graphProcessingState integer, mediaAnalysisProcessingState integer, mediaAnalysisData blob, mediaAnalysisVersion integer, statViewCount integer, statPlayCount integer, statShareCount integer, curationScore decimal, fileIsReference integer, groupingUuid varchar, playbackStyle integer, playbackVariation integer, renderEffect integer, groupingState integer, cloudGroupingState integer, importMomentId integer, selfPortrait integer, syncFailureHidden integer, searchIndexInvalid integer);

# コピーした情報からマスターの imagePath を調べる

sqlite> select * from RKVersion where modelId=24761;
sqlite> select * from RKVersion where uuid='RVBB6Db9R7m4BB7rieDOUQ';

sqlite> select RKMaster.imagePath from RKVersion inner join RKMaster on RKVersion.masterId=RKMaster.modelId where RKVersion.uuid='RVBB6Db9R7m4BB7rieDOUQ';
2013/06/08/20130608-123808/IMG_3865.JPG

open ~/Pictures/写真\ Library.photoslibrary/Masters/2013/06/08/20130608-123808/IMG_3865.JPG
