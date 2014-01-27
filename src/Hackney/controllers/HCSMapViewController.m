/** Cycle Atlanta, Copyright 2012, 2013 Georgia Institute of Technology
 *                                    Atlanta, GA. USA
 *
 *   @author Christopher Le Dantec <ledantec@gatech.edu>
 *   @author Anhong Guo <guoanhong@gatech.edu>
 *
 *   Updated/Modified for Atlanta's app deployment. Based on the
 *   CycleTracks codebase for SFCTA.
 *
 ** CycleTracks, Copyright 2009,2010 San Francisco County Transportation Authority
 *                                    San Francisco, CA, USA
 *
 *   @author Matt Paul <mattpaul@mopimp.com>
 *
 *   This file is part of CycleTracks.
 *
 *   CycleTracks is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   CycleTracks is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with CycleTracks.  If not, see <http://www.gnu.org/licenses/>.
 */

//
//  MapViewController.m
//  CycleTracks
//
//  Copyright 2009-2010 SFCTA. All rights reserved.
//  Written by Matt Paul <mattpaul@mopimp.com> on 9/28/09.
//	For more information on the project,
//	e-mail Billy Charlton at the SFCTA <billy.charlton@sfcta.org>


#import "Coord.h"
#import "LoadingView.h"
#import "MapCoord.h"
#import "HCSMapViewController.h"
#import "Trip.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import "RMMapView.h"
#import "RMAnnotation.h"
#import "RMMarker.h"
#import "UserLocationManager.h"

#import "GlobalUtilities.h"
#import "LayoutBox.h"
// cs compatability classes
#import "CSPointVO.h"
#import "RouteVO.h"
#import "SegmentVO.h"
#import "ExpandedUILabel.h"
#import "HudManager.h"

#define kFudgeFactor	1.5
#define kInfoViewAlpha	0.8
#define kMinLatDelta	0.0039
#define kMinLonDelta	0.0034

@interface HCSMapViewController()<RMMapViewDelegate>


@property(nonatomic,weak) IBOutlet UINavigationItem					*myNavigationItem;

@property (nonatomic, strong) Trip									*trip;
@property (nonatomic, strong) UIBarButtonItem						*doneButton;
@property (nonatomic, strong) UIBarButtonItem						*flipButton;
@property (nonatomic, strong) LayoutBox								*infoView;

@property (nonatomic,weak) IBOutlet UILabel							*routeInfoLabel;


@property (nonatomic,weak) IBOutlet RMMapView						*mapView;
@property (nonatomic,weak) IBOutlet RouteLineView					*routeLineView;

@property (nonatomic,strong) RouteVO								*currentRoute;


@end


@implementation HCSMapViewController


- (id)initWithTrip:(Trip *)trip
{

	if (self = [super initWithNibName:@"HCSMapViewController" bundle:nil]) {
		NSLog(@"MapViewController initWithTrip");
		self.trip = trip;
    }
    return self;
}



- (void)infoAction:(UIButton*)sender
{
	NSLog(@"infoAction");
	[UIView setAnimationDelegate:self];
	[UIView setAnimationDidStopSelector:@selector(animationDidStop:animationIDfinished:finished:context:)];
	[UIView beginAnimations:nil context:nil];
	[UIView setAnimationDuration:0.75];
	
	[UIView setAnimationTransition:([_infoView superview] ?
									UIViewAnimationTransitionFlipFromLeft : UIViewAnimationTransitionFlipFromRight)
						   forView:self.view cache:YES];
	
	if ([_infoView superview])
		[_infoView removeFromSuperview];
	else
		[self.view addSubview:_infoView];
	
	[UIView commitAnimations];
	
	// adjust our done/info buttons accordingly
	if ([_infoView superview] == self.view)
		_myNavigationItem.rightBarButtonItem = _doneButton;
	else
		_myNavigationItem.rightBarButtonItem = _flipButton;
}


- (void)initInfoView
{
	
	_infoView=[[LayoutBox alloc]initWithFrame:CGRectMake(0,64,320,560)];
	_infoView.fixedWidth=YES;
	_infoView.fixedHeight=YES;
	_infoView.paddingLeft=10;
	_infoView.itemPadding=20;
	_infoView.backgroundColor=UIColorFromRGBAndAlpha(0x000000, kInfoViewAlpha);
	
	
	ExpandedUILabel *notesHeader=[[ExpandedUILabel alloc]initWithFrame:CGRectMake(0, 0, _infoView.width, 10)];
	notesHeader.fixedWidth=YES;
	notesHeader.font=[UIFont fontWithName:@"HelveticaNeue-Light" size:18];
	notesHeader.textColor=UIColorFromRGB(0xFFFFFF);
	notesHeader.text = @"Trip Notes";
	[_infoView addSubview:notesHeader];
	
	ExpandedUILabel *notesText=[[ExpandedUILabel alloc]initWithFrame:CGRectMake(0, 0, _infoView.width, 10)];
	notesText.fixedWidth=YES;
	notesHeader.font=[UIFont fontWithName:@"HelveticaNeue-Regular" size:16];
	notesHeader.textColor=UIColorFromRGB(0xFFFFFF);
	notesHeader.text = _trip.notes;
	[_infoView addSubview:notesText];
    
}



- (void)viewDidLoad
{
    [super viewDidLoad];
	
	[RMMapView class];
	[_mapView setDelegate:self];
	_mapView.enableDragging=YES;
	
	_routeLineView.pointListProvider=self;
	
    self.navigationController.navigationBarHidden = YES;
	
    
	if (_trip )
	{
		// format date as a string
		static NSDateFormatter *dateFormatter = nil;
		if (dateFormatter == nil) {
			dateFormatter = [[NSDateFormatter alloc] init];
			[dateFormatter setTimeStyle:NSDateFormatterShortStyle];
			[dateFormatter setDateStyle:NSDateFormatterLongStyle];
		}
		
		// display duration, distance as navbar prompt
		static NSDateFormatter *inputFormatter = nil;
		if ( inputFormatter == nil )
			inputFormatter = [[NSDateFormatter alloc] init];
		
		[inputFormatter setDateFormat:@"HH:mm:ss"];
		NSDate *fauxDate = [inputFormatter dateFromString:@"00:00:00"];
		[inputFormatter setDateFormat:@"HH:mm:ss"];
		NSDate *outputDate = [[NSDate alloc] initWithTimeInterval:(NSTimeInterval)[_trip.duration doubleValue] sinceDate:fauxDate];
        
		double mph = ( [_trip.distance doubleValue] / 1609.344 ) / ( [_trip.duration doubleValue] / 3600. );
		
		self.routeInfoLabel.text = [NSString stringWithFormat:@"elapsed: %@ ~ %@",
 									  [inputFormatter stringFromDate:outputDate],
									  [dateFormatter stringFromDate:[_trip start]]];
        
		_myNavigationItem.title = [NSString stringWithFormat:@"%.1f mi ~ %.1f mph", [_trip.distance doubleValue] / 1609.344, mph ];
		
		
		// only add info view for trips with non-null notes
		if ( ![_trip.notes isEqualToString:EMPTYSTRING] && _trip.notes != nil)
		{
			_doneButton = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStylePlain target:self action:@selector(infoAction:)];
			
			UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
			infoButton.showsTouchWhenHighlighted = YES;
			[infoButton addTarget:self action:@selector(infoAction:) forControlEvents:UIControlEventTouchUpInside];
			_flipButton = [[UIBarButtonItem alloc] initWithCustomView:infoButton];
			_myNavigationItem.rightBarButtonItem = _flipButton;
			
			[self initInfoView];
		}
		
        
				
		// filter coords by hAccuracy
		NSPredicate *filterByAccuracy	= [NSPredicate predicateWithFormat:@"hAccuracy < 6.0"];
		NSArray		*filteredCoords		= [[_trip.coords allObjects] filteredArrayUsingPredicate:filterByAccuracy];
		NSLog(@"count of filtered coords = %d", [filteredCoords count]);
		
		// sort filtered coords by recorded date
		NSSortDescriptor *sortByDate	= [[NSSortDescriptor alloc] initWithKey:@"recorded" ascending:YES];
		NSArray		*sortDescriptors	= [NSArray arrayWithObjects:sortByDate, nil];
		NSArray		*sortedCoords		= [filteredCoords sortedArrayUsingDescriptors:sortDescriptors];
		
		// add coords as annotations to map
		BOOL first = YES;
		Coord *last = nil;
		MapCoord *pin = nil;
		int count = 0;
		
		// calculate min/max values for lat, lon
		NSNumber *minLat = [NSNumber numberWithDouble:0.0];
		NSNumber *maxLat = [NSNumber numberWithDouble:0.0];
		NSNumber *minLon = [NSNumber numberWithDouble:0.0];
		NSNumber *maxLon = [NSNumber numberWithDouble:0.0];
        
        NSMutableArray *routeCoords = [[NSMutableArray alloc]init];
		
		
		NSNumberFormatter *doubleValueWithMaxTwoDecimalPlaces = [[NSNumberFormatter alloc] init];
		[doubleValueWithMaxTwoDecimalPlaces setNumberStyle:NSNumberFormatterDecimalStyle];
		[doubleValueWithMaxTwoDecimalPlaces setMaximumFractionDigits:4];
		
		self.currentRoute=[[RouteVO alloc]init];
        
		for ( Coord *coord in sortedCoords ){
			
			
			NSNumber *newlat=[NSNumber numberWithDouble:[[doubleValueWithMaxTwoDecimalPlaces stringFromNumber:coord.latitude] doubleValue]];
			NSNumber *newlongt=[NSNumber numberWithDouble:[[doubleValueWithMaxTwoDecimalPlaces stringFromNumber:coord.longitude] doubleValue]];
			
			coord.latitude=newlat;
			coord.longitude=newlongt;
			
			// only plot unique coordinates to our map for performance reasons
			if ( !last ||
				(![coord.latitude  isEqualToNumber:last.latitude] &&
				 ![coord.longitude isEqualToNumber:last.longitude] ) ){
					
				
					// this is a bit convoluted but meets comaptibility for routeline drawing
					SegmentVO *segment=[[SegmentVO alloc]init];
					CSPointVO *point=[[CSPointVO alloc]init];
					point.p=CGPointMake([coord.longitude doubleValue],[coord.latitude doubleValue]);
					segment.pointsArray=@[point];
					
					[routeCoords addObject:segment];
                
					if ( first ){
						
						// add start point as a pin annotation
						first = NO;
						
						minLat = coord.latitude;
						maxLat = coord.latitude;
						minLon = coord.longitude;
						maxLon = coord.longitude;
					}else{
						
						// update min/max values
						if ( [minLat compare:coord.latitude] == NSOrderedDescending )
							minLat = coord.latitude;
						
						if ( [maxLat compare:coord.latitude] == NSOrderedAscending )
							maxLat = coord.latitude;
						
						if ( [minLon compare:coord.longitude] == NSOrderedDescending )
							minLon = coord.longitude;
						
						if ( [maxLon compare:coord.longitude] == NSOrderedAscending )
							maxLon = coord.longitude;
					}
					
					//[mapView addAnnotation:pin];
					count++;
			}
			
			// update last coord pointer so we can cull redundant coords above
			last = coord;
		}
		
		_currentRoute.segments=routeCoords;
        
		[_routeLineView setNeedsDisplay];
        
        //add start/end pins
        RMAnnotation *startPoint = [[RMAnnotation alloc] init];
		SegmentVO *firstsegment=(SegmentVO*)[_currentRoute.segments firstObject];
        startPoint.coordinate = firstsegment.segmentStart;
        startPoint.title = @"Start";
		startPoint.annotationIcon=[UIImage imageNamed:@"tripStart.png"];
        [_mapView addAnnotation:startPoint];
        RMAnnotation *endPoint = [[RMAnnotation alloc] init];
		SegmentVO *lastsegment=(SegmentVO*)[_currentRoute.segments lastObject];
        endPoint.coordinate = lastsegment.segmentStart;
        endPoint.title = @"End";
		endPoint.annotationIcon=[UIImage imageNamed:@"tripEnd.png"];
        [_mapView addAnnotation:endPoint];
        
				
		
		NSLog(@"added %d unique GPS coordinates of %d to map", count, [sortedCoords count]);
		
		// add end point as a pin annotation
		if ( last == [sortedCoords lastObject] )
		{
			pin.last = YES;
			pin.title = @"End";
			pin.subtitle = [dateFormatter stringFromDate:last.recorded];
		}
		
		// if we had at least 1 coord
		if ( count ){
			
			[_currentRoute calculateNorthSouthValues];
			
			CLLocationCoordinate2D ne=[_currentRoute insetNorthEast];
			CLLocationCoordinate2D sw=[_currentRoute insetSouthWest];
			[_mapView zoomWithLatitudeLongitudeBoundsSouthWest:sw northEast:ne animated:YES];
			
		}else{
			[_mapView setCenterCoordinate:[UserLocationManager defaultCoordinate]];
		}
        
	}else{
		[_mapView setCenterCoordinate:[UserLocationManager defaultCoordinate]];
	}
    
	[[HudManager sharedInstance] showHudWithType:HUDWindowTypeSuccess withTitle:@"Route loaded" andMessage:nil andDelay:1 andAllowTouch:NO];
	
	
}



#pragma mark - Route line point list provider
// PointListProvider
+ (NSArray *) pointList:(RouteVO *)route withView:(RMMapView *)mapView {
	
	NSMutableArray *points = [[NSMutableArray alloc] initWithCapacity:10];
	if (route == nil) {
		return points;
	}
	
	for (int i = 0; i < [route numSegments]; i++) {
			CSPointVO *p = [[CSPointVO alloc] init];
			SegmentVO *segment = [route segmentAtIndex:i];
			CLLocationCoordinate2D coordinate = [segment segmentStart];
			CGPoint pt = [mapView coordinateToPixel:coordinate];
			p.p = pt;
			p.isWalking=segment.isWalkingSection;
			[points addObject:p];
//		}
//		// remainder of all segments
//		SegmentVO *segment = [route segmentAtIndex:i];
//		NSArray *allPoints = [segment allPoints];
//		for (int i = 0; i < [allPoints count]; i++) {
//			CSPointVO *latlon = [allPoints objectAtIndex:i];
//			CLLocationCoordinate2D coordinate;
//			coordinate.latitude = latlon.p.y;
//			coordinate.longitude = latlon.p.x;
//			CGPoint pt = [mapView coordinateToPixel:coordinate];
//			CSPointVO *screen = [[CSPointVO alloc] init];
//			screen.p = pt;
//			screen.isWalking=segment.isWalkingSection;
//			[points addObject:screen];
//		}
	}
	
	return points;
}

- (NSArray *) pointList {
	return [HCSMapViewController pointList:_currentRoute withView:_mapView];
}



#pragma mark - Screen shot support

- (void)viewWillDisappear:(BOOL)animated{
    UIImage *thumbnailOriginal;
    thumbnailOriginal = [self screenshot];
    
    CGRect clippedRect  = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y+160, self.view.frame.size.width, self.view.frame.size.height);
    CGImageRef imageRef = CGImageCreateWithImageInRect([thumbnailOriginal CGImage], clippedRect);
    UIImage *newImage   = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    
    CGSize size;
    size.height = 72;
    size.width = 72;
    
    UIImage *thumbnail;
    thumbnail = shrinkImage(newImage, size);
    
    NSData *thumbnailData = [[NSData alloc] initWithData:UIImageJPEGRepresentation(thumbnail, 0)];
    NSLog(@"Size of Thumbnail Image(bytes):%d",[thumbnailData length]);
    NSLog(@"Size: %f, %f", thumbnail.size.height, thumbnail.size.width);
    
    [self.delegate getTripThumbnail:thumbnailData];
}


UIImage *shrinkImage(UIImage *original, CGSize size) {
    CGFloat scale = [UIScreen mainScreen].scale;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	
	CGImageRef imageRef = CGImageCreateCopy([original CGImage]);
	CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(imageRef);
	
	if (CGColorSpaceGetNumberOfComponents(colorSpace) == 3) {
        int alpha = (bitmapInfo & kCGBitmapAlphaInfoMask);
        if (alpha == kCGImageAlphaNone) {
            bitmapInfo &= ~kCGBitmapAlphaInfoMask;
            bitmapInfo |= kCGImageAlphaNoneSkipFirst;
        } else if (!(alpha == kCGImageAlphaNoneSkipFirst || alpha == kCGImageAlphaNoneSkipLast)) {
            bitmapInfo &= ~kCGBitmapAlphaInfoMask;
            bitmapInfo |= kCGImageAlphaPremultipliedFirst;
        }
    }
	
    
    CGContextRef context = CGBitmapContextCreate(NULL, size.width * scale,
                                                 size.height * scale, 8, 0, colorSpace, bitmapInfo);
    CGContextDrawImage(context,
                       CGRectMake(0, 0, size.width * scale, size.height * scale),
                       original.CGImage);
    CGImageRef shrunken = CGBitmapContextCreateImage(context);
    UIImage *final = [UIImage imageWithCGImage:shrunken];
    
    CGContextRelease(context);
    CGImageRelease(shrunken);
    CGColorSpaceRelease(colorSpace);
    return final;
}


- (UIImage*)screenshot
{
    NSLog(@"Screen Shoot");
    // Create a graphics context with the target size
    // On iOS 4 and later, use UIGraphicsBeginImageContextWithOptions to take the scale into consideration
    // On iOS prior to 4, fall back to use UIGraphicsBeginImageContext
    CGSize imageSize = [[UIScreen mainScreen] bounds].size;
    if (NULL != UIGraphicsBeginImageContextWithOptions)
        UIGraphicsBeginImageContextWithOptions(imageSize, NO, 0);
    else
        UIGraphicsBeginImageContext(imageSize);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Iterate over every window from back to front
    for (UIWindow *window in [[UIApplication sharedApplication] windows])
    {
        if (![window respondsToSelector:@selector(screen)] || [window screen] == [UIScreen mainScreen])
        {
            // -renderInContext: renders in the coordinate space of the layer,
            // so we must first apply the layer's geometry to the graphics context
            CGContextSaveGState(context);
            // Center the context around the window's anchor point
            CGContextTranslateCTM(context, [window center].x, [window center].y);
            // Apply the window's transform about the anchor point
            CGContextConcatCTM(context, [window transform]);
            // Offset by the portion of the bounds left of and above the anchor point
            CGContextTranslateCTM(context,
                                  -[window bounds].size.width * [[window layer] anchorPoint].x,
                                  -[window bounds].size.height * [[window layer] anchorPoint].y+50);
            
            // Render the layer hierarchy to the current context
            [[window layer] renderInContext:context];
            
            // Restore the context
            CGContextRestoreGState(context);
        }
    }
    
    // Retrieve the screenshot image
    UIImage *screenImage = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return screenImage;
}



#pragma mark User events






#pragma mark RMMapView delegate methods


-(void)doubleTapOnMap:(RMMapView*)map At:(CGPoint)point{
	
}

-(void) beforeMapMove:(RMMapView *)map byUser:(BOOL)wasUserAction{
	//[_routeLineView setNeedsDisplay];
}

- (void) afterMapZoom: (RMMapView*) map byFactor: (float) zoomFactor near:(CGPoint) center {
	[_routeLineView setNeedsDisplay];
}

- (void) afterMapMove:(RMMapView *)map byUser:(BOOL)wasUserAction{
	
	[_routeLineView setNeedsDisplay];
}

-(void)mapViewRegionDidChange:(RMMapView *)mapView{
	[_routeLineView setNeedsDisplay];
}


- (RMMapLayer *)mapView:(RMMapView *)aMapView layerForAnnotation:(RMAnnotation *)annotation {
	//NSLog(@"viewForAnnotation");
	
    // If it's the user location, just return nil.
    if ([annotation isKindOfClass:[MKUserLocation class]])
        return nil;
	
    // Handle any custom annotations.
    if ([annotation isKindOfClass:[MapCoord class]]){
		
		RMMapLayer* annotationView = nil;
		
		if ( [(MapCoord*)annotation first] ){
		
			annotationView = [[RMMarker alloc] initWithUIImage:annotation.annotationIcon anchorPoint:annotation.anchorPoint];
			
		} else if ( [(MapCoord*)annotation last] ){
			
			annotationView = [[RMMarker alloc] initWithUIImage:annotation.annotationIcon anchorPoint:annotation.anchorPoint];
			
		}else{
			
			annotationView = [[RMMarker alloc] initWithUIImage:annotation.annotationIcon anchorPoint:annotation.anchorPoint];
			
			
		}
		
        return annotationView;
    } else {
        //handle 'normal' pins
        
        RMMapLayer *annotationView = [[RMMarker alloc] initWithUIImage:annotation.annotationIcon anchorPoint:annotation.anchorPoint];
		
		return annotationView;
    }
	
    return nil;
}




- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}



@end