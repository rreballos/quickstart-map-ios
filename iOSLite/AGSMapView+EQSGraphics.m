//
//  AGSMapView+Graphics.m
//  EsriQuickStartApp
//
//  Created by Nicholas Furness on 5/23/12.
//  Copyright (c) 2012 ESRI. All rights reserved.
//

#import "EQSBasemapsNotifications.h"
#import "AGSMapView+EQSGraphics.h"
#import "AGSMapView+GeneralUtilities.h"
#import "AGSPoint+GeneralUtilities.h"

#import "EQSGraphicCallout.h"

#import "EQSHelper.h"

@implementation AGSMapView (EQSGraphics)
AGSGraphicsLayer * __eqsPointGraphicsLayer = nil;
AGSGraphicsLayer * __eqsPolylineGraphicsLayer = nil;
AGSGraphicsLayer * __eqsPolygonGraphicsLayer = nil;
AGSSketchGraphicsLayer * __eqsSketchGraphicsLayer = nil;
id<AGSMapViewTouchDelegate> __eqsTempTouchDelegate = nil;

AGSGraphic * __eqsCurrentEditingGraphic = nil;

EQSGraphicCallout *__eqsTheGraphicCallout = nil;

#define kEQSGraphicsLayerName_Point @"eqsPointGraphicsLayer"
#define kEQSGraphicsLayerName_Polyline @"eqsPolylineGraphicsLayer"
#define kEQSGraphicsLayerName_Polygon @"eqsPolygonGraphicsLayer"

#define kEQSGraphicTag @"esriQuickStartLib"
#define kEQSGraphicTagKey @"createdBy"

#define kEQSSketchGraphicsLayerName @"eqsSketchGraphcisLayer"

#pragma mark - Add Graphics Programatically
- (AGSGraphic *) addPointAtLat:(double)latitude lon:(double)longitude
{
    AGSPoint *pt = [AGSPoint pointFromLat:latitude lon:longitude];
    
	return [self addPoint:pt];
}

- (AGSGraphic *) addPoint:(AGSPoint *)point
{
    AGSGraphic *g = [self __eqsGetDefaultGraphicForGeometry:[point getWebMercatorAuxSpherePoint]];
    
    [self __eqsAddGraphicToAppropriateGraphicsLayer:g];
    
    return g;
}

- (AGSGraphic *) addPointAtLat:(double)latitude lon:(double)longitude withSymbol:(AGSMarkerSymbol *)markerSymbol
{
    AGSPoint *pt = [AGSPoint pointFromLat:latitude lon:longitude];

    return [self addPoint:pt withSymbol:markerSymbol];
}

- (AGSGraphic *) addPoint:(AGSPoint *)point withSymbol:(AGSMarkerSymbol *)markerSymbol
{
    AGSGraphic *g = [self __eqsGetDefaultGraphicForGeometry:[point getWebMercatorAuxSpherePoint]];
    g.symbol = markerSymbol;
    [self __eqsAddGraphicToAppropriateGraphicsLayer:g];
    return g;
}


- (AGSGraphic *) addLineFromPoints:(NSArray *) points
{
	NSAssert1(points.count > 1, @"Must provide at least 2 points!", points.count);

    AGSMutablePolyline *line = [[AGSMutablePolyline alloc] initWithSpatialReference:[AGSSpatialReference webMercatorSpatialReference]];
    [line addPathToPolyline];

    for (AGSPoint *pt in points)
    {
        [line addPointToPath:[pt getWebMercatorAuxSpherePoint]];
    }

    AGSGraphic *g = [self __eqsGetDefaultGraphicForGeometry:line];

    [self __eqsAddGraphicToAppropriateGraphicsLayer:g];

    return g;
}

- (AGSGraphic *) addPolygonFromPoints:(NSArray *) points
{
    NSAssert1(points.count > 2, @"Must provide at least 3 points for a polygon!", points.count);

    AGSMutablePolygon *poly = [[AGSMutablePolygon alloc] initWithSpatialReference:[AGSSpatialReference webMercatorSpatialReference]];
    [poly addRingToPolygon];

    for (AGSPoint *pt in points)
    {
        [poly addPointToRing:[pt getWebMercatorAuxSpherePoint]];
    }

    AGSGraphic *g = [self __eqsGetDefaultGraphicForGeometry:poly];

    [self __eqsAddGraphicToAppropriateGraphicsLayer:g];

    return g;
}

#pragma mark - Clear graphics from the map
- (void) clearGraphics:(EQSGraphicsLayerType)layerType
{
    AGSGraphicsLayer *gl = nil;
    if (layerType & EQSGraphicsLayerTypePoint)
    {
        gl = [self getGraphicsLayer:EQSGraphicsLayerTypePoint];
        [gl removeAllGraphics];
        [gl dataChanged];
    }
    
    if (layerType & EQSGraphicsLayerTypePolyline)
    {
        gl = [self getGraphicsLayer:EQSGraphicsLayerTypePolyline];
        [gl removeAllGraphics];
        [gl dataChanged];
    }
    
    if (layerType & EQSGraphicsLayerTypePolygon)
    {
        gl = [self getGraphicsLayer:EQSGraphicsLayerTypePolygon];
        [gl removeAllGraphics];
        [gl dataChanged];
    }
}

- (void) clearGraphics
{
    [self clearGraphics:(EQSGraphicsLayerTypePoint + 
                         EQSGraphicsLayerTypePolyline +
                         EQSGraphicsLayerTypePolygon)];
}

#pragma mark - Add graphic
- (AGSGraphicsLayer *) addGraphic:(AGSGraphic *)graphic
{
    return [self __eqsAddGraphicToAppropriateGraphicsLayer:graphic];
}

- (AGSGraphicsLayer *) addGraphic:(AGSGraphic *)graphic withAttribute:(id)attribute withValue:(id)value
{
    AGSGraphicsLayer *targetLayer = [self __eqsGetAppropriateGraphicsLayerForGraphic:graphic];
    if (!graphic.attributes)
    {
        graphic.attributes = [NSMutableDictionary dictionaryWithCapacity:1];
    }
    [graphic.attributes setObject:value forKey:attribute];
    [targetLayer addGraphic:graphic];
    [targetLayer dataChanged];
    return targetLayer;
}


#pragma mark - Remove graphic
- (AGSGraphicsLayer *) removeGraphic:(AGSGraphic *)graphic
{
    AGSGraphicsLayer *owningLayer = [self removeGraphicNoRefresh:graphic];
    if (owningLayer)
    {
        [owningLayer dataChanged];
    }
    
    return owningLayer;
}

- (AGSGraphicsLayer *) removeGraphicNoRefresh:(AGSGraphic *)graphic
{
	if (graphic)
	{
		if (graphic.layer)
		{
            AGSGraphicsLayer *owningLayer = graphic.layer;
			[graphic.layer removeGraphic:graphic];
            return owningLayer;
		}
	}
    return nil;
}

- (NSSet *) removeGraphicsMatchingCriteria:(BOOL (^)(AGSGraphic *graphic))checkBlock
{
    NSArray *layersToCheck = [NSArray arrayWithObjects:__eqsPointGraphicsLayer,
                                                       __eqsPolylineGraphicsLayer, 
                                                       __eqsPolygonGraphicsLayer, nil];
    
    // Get the graphics to remove from all layers
    NSMutableArray *graphicsToRemove = [NSMutableArray array];
    for (AGSGraphicsLayer *gl in layersToCheck) {
        for (AGSGraphic *g in gl.graphics) {
            if (checkBlock(g))
            {
                [graphicsToRemove addObject:g];
            }
        }
    }
    
    // Remove each graphic from its layer, and remember the set of layers affected
    NSMutableSet *layersToUpdate = [NSMutableSet set];
    for (AGSGraphic *g in graphicsToRemove) {
        [layersToUpdate addObject:g.layer];
        [self removeGraphicNoRefresh:g];
    }
    
    // Flag the affected layers for redraw
    for (AGSGraphicsLayer *gl in layersToUpdate)
    {
        [gl dataChanged];
    }
    
    return layersToUpdate;
}

- (NSSet *) removeGraphicsByAttribute:(id)attribute withValue:(id)value
{
    return [self removeGraphicsMatchingCriteria:^BOOL(AGSGraphic *graphic) {
        return [[graphic.attributes objectForKey:attribute] isEqual:value];
    }];
}

#pragma mark - Edit graphic
- (void) editGraphic:(AGSGraphic *)graphic
{
	[self __eqsEditGraphic:graphic];
}

#pragma mark - Edit graphic selected from the map
- (AGSGraphic *) editGraphicFromMapViewDidClickAtPoint:(NSDictionary *)graphics
{
    AGSGraphic *graphicToEdit = nil;
    
    for (NSString *layerName in graphics.allKeys)
    {
        if (layerName == kEQSGraphicsLayerName_Point ||
            layerName == kEQSGraphicsLayerName_Polyline ||
            layerName == kEQSGraphicsLayerName_Polygon)
        {
            NSArray *graphicsToEditFromLayer = [graphics objectForKey:layerName];
            if (graphicsToEditFromLayer.count > 0)
            {
                graphicToEdit = [graphicsToEditFromLayer objectAtIndex:0];
                break;
            }
        }
    }
	
	[self editGraphic:graphicToEdit];
    
    return graphicToEdit;
}

#pragma mark - Create and Edit new graphics
- (void) createAndEditNewPoint
{
    [self __eqsEditGeometry:[[AGSMutablePoint alloc] initWithSpatialReference:[AGSSpatialReference webMercatorSpatialReference]]];
}

- (void) createAndEditNewMultipoint
{
    [self __eqsEditGeometry:[[AGSMutableMultipoint alloc] initWithSpatialReference:[AGSSpatialReference webMercatorSpatialReference]]];
}

- (void) createAndEditNewLine
{
    [self __eqsEditGeometry:[[AGSMutablePolyline alloc] initWithSpatialReference:[AGSSpatialReference webMercatorSpatialReference]]];
}

- (void) createAndEditNewPolygon
{
    [self __eqsEditGeometry:[[AGSMutablePolygon alloc] initWithSpatialReference:[AGSSpatialReference webMercatorSpatialReference]]];
}

#pragma mark - Save edit/create
- (AGSGraphic *) saveGraphicEdit
{
    if (__eqsSketchGraphicsLayer)
    {
        // Update the graphics geometry
        AGSGeometry *editedGeometry = __eqsSketchGraphicsLayer.geometry;
        AGSGraphic *editedGraphic = nil;
        if (__eqsCurrentEditingGraphic)
        {
            // Editing an existing graphic
            __eqsCurrentEditingGraphic.geometry = editedGeometry;
            AGSGraphicsLayer *owningLayer = __eqsCurrentEditingGraphic.layer;
            // Get the owning layer and refresh it.
            [owningLayer dataChanged];
            
            editedGraphic = __eqsCurrentEditingGraphic;
        }
        else
        {
            // Creating a new graphic
            AGSGraphic *g = [self __eqsGetDefaultGraphicForGeometry:editedGeometry];
            [self __eqsAddGraphicToAppropriateGraphicsLayer:g];

            // Set the info template delegate
            if (!__eqsTheGraphicCallout)
            {
                __eqsTheGraphicCallout = [[EQSGraphicCallout alloc] init];
            }
            g.infoTemplateDelegate = __eqsTheGraphicCallout;
            
            editedGraphic = g;
        }
        
        // Set the UI interaction back to how it was before.
        __eqsSketchGraphicsLayer.geometry = nil;
        __eqsCurrentEditingGraphic = nil;
        self.touchDelegate = __eqsTempTouchDelegate;
        __eqsTempTouchDelegate = nil;
        
        return editedGraphic;
    }
    
    return nil;
}

#pragma mark - Cancel edit/create
- (AGSGraphic *) cancelGraphicEdit
{
    if (__eqsSketchGraphicsLayer)
    {
        AGSGraphic *graphicToReturn = __eqsCurrentEditingGraphic;
        // Set the UI interaction back to how it was before.
        __eqsSketchGraphicsLayer.geometry = nil;
        __eqsCurrentEditingGraphic = nil;
        self.touchDelegate = __eqsTempTouchDelegate;
        __eqsTempTouchDelegate = nil;
        return graphicToReturn;
    }
    
    return nil;
}

#pragma mark - Undo/Redo
- (void)undoGraphicEdit
{
    [[self getUndoManagerForGraphicsEdits] undo];
}

- (void)redoGraphicEdit
{
    [[self getUndoManagerForGraphicsEdits] redo];
}

- (NSUndoManager *) registerListener:(id)object ForEditGraphicUndoRedoNotificationsUsing:(SEL)handlerMethod
{
    [self stop:object ListeningForEditGraphicUndoRedoNotificationsOn:nil];
    
    NSUndoManager *um = [self getUndoManagerForGraphicsEdits];
    if (um)
    {
        [[NSNotificationCenter defaultCenter] addObserver:object
                                                 selector:handlerMethod
                                                     name:@"NSUndoManagerDidCloseUndoGroupNotification"
                                                   object:um];
        [[NSNotificationCenter defaultCenter] addObserver:object
                                                 selector:handlerMethod
                                                     name:@"NSUndoManagerDidUndoChangeNotification"
                                                   object:um];
        [[NSNotificationCenter defaultCenter] addObserver:object
                                                 selector:handlerMethod
                                                     name:@"NSUndoManagerDidRedoChangeNotification"
                                                   object:um];
    }
    return um;
}

- (void) stop:(id)listener ListeningForEditGraphicUndoRedoNotificationsOn:(NSUndoManager *)manager
{
    [[NSNotificationCenter defaultCenter] removeObserver:listener
                                                    name:@"NSUndoManagerDidCloseUndoGroupNotification"
                                                  object:manager];
    [[NSNotificationCenter defaultCenter] removeObserver:listener
                                                    name:@"NSUndoManagerDidUndoChangeNotification"
                                                  object:manager];
    [[NSNotificationCenter defaultCenter] removeObserver:listener
                                                    name:@"NSUndoManagerDidRedoChangeNotification"
                                                  object:manager];
}


#pragma mark - Accessors to useful objects for UI feedback during editing
- (NSUndoManager *) getUndoManagerForGraphicsEdits
{
    if (__eqsSketchGraphicsLayer)
    {
        return __eqsSketchGraphicsLayer.undoManager;
    }
    return nil;
}

- (AGSGeometry *) getCurrentEditGeometry
{
    if (__eqsSketchGraphicsLayer)
    {
        return __eqsSketchGraphicsLayer.geometry;
    }
    return nil;
}

- (AGSGraphic *) getCurrentEditGraphic
{
    return __eqsCurrentEditingGraphic;
}

- (AGSGraphicsLayer *) getGraphicsLayer:(EQSGraphicsLayerType)layerType
{
    if (!__eqsPointGraphicsLayer)
    {
        // Create three graphics layers and add them to the map.
        __eqsPointGraphicsLayer = [AGSGraphicsLayer graphicsLayer];
        __eqsPolylineGraphicsLayer = [AGSGraphicsLayer graphicsLayer];
        __eqsPolygonGraphicsLayer = [AGSGraphicsLayer graphicsLayer];
        // And register our interest in basemap changes so we can re-add the layers if need be.
		[[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(__eqsGraphicsBasemapDidChange:) 
                                                     name:kEQSNotification_BasemapDidChange
                                                   object:self];
        
    }
    
    [self __ensureEQSGraphicsLayersAdded];
    
    switch (layerType) {
        case EQSGraphicsLayerTypePoint:
            return __eqsPointGraphicsLayer;
            
        case EQSGraphicsLayerTypePolyline:
            return __eqsPolylineGraphicsLayer;
            
        case EQSGraphicsLayerTypePolygon:
            return __eqsPolygonGraphicsLayer;
    }
    
    return nil;
}

#pragma mark - Internal/Private

- (void) __eqsEditGraphic:(AGSGraphic *)graphicToEdit
{
    if (graphicToEdit)
    {
        [self __eqsEditGeometry:graphicToEdit.geometry];
        __eqsCurrentEditingGraphic = graphicToEdit;
    }
}

- (void) __eqsEditGeometry:(AGSGeometry *)geom
{
    if (geom)
    {
        if (!__eqsSketchGraphicsLayer)
        {
            __eqsSketchGraphicsLayer = [AGSSketchGraphicsLayer graphicsLayer];
        }
        
        // The layer should always be the topmost layer so, even if we've added it previously, let's
        // remove it now so we can add it to the top again.
        if (![self getLayerForName:kEQSSketchGraphicsLayerName])
        {
            [self removeMapLayerWithName:kEQSSketchGraphicsLayerName];
        }

        [self addMapLayer:__eqsSketchGraphicsLayer withName:kEQSSketchGraphicsLayerName];
        
        // Store the real touch delegate
        if (!__eqsTempTouchDelegate &&
            self.touchDelegate != __eqsSketchGraphicsLayer)
        {
            __eqsTempTouchDelegate = self.touchDelegate;
        }
        
        // Set the sketch layer to be the touch delegate.
        self.touchDelegate = __eqsSketchGraphicsLayer;
        
        AGSGeometry *editGeom = nil;
        editGeom = [geom mutableCopy];
        __eqsSketchGraphicsLayer.geometry = editGeom;
    }
}

- (void) __ensureEQSGraphicsLayersAdded
{
	if (![self getLayerForName:kEQSGraphicsLayerName_Polygon])
    {
        [self addMapLayer:__eqsPolygonGraphicsLayer withName:kEQSGraphicsLayerName_Polygon];
    }
	
    if (![self getLayerForName:kEQSGraphicsLayerName_Polyline])
    {
        [self addMapLayer:__eqsPolylineGraphicsLayer withName:kEQSGraphicsLayerName_Polyline];
    }
    
    if (![self getLayerForName:kEQSGraphicsLayerName_Point])
    {
        [self addMapLayer:__eqsPointGraphicsLayer withName:kEQSGraphicsLayerName_Point];
    }
}

- (void) __initEQSGraphics
{
    // Asking for any layer will ensure they're all created and added.
    [self getGraphicsLayer:EQSGraphicsLayerTypePoint];
}

- (void) __eqsGraphicsBasemapDidChange:(NSNotification *)notification
{
	[self __ensureEQSGraphicsLayersAdded];
}

- (AGSSymbol *) __eqsGetDefaultSymbolForGeometry:(AGSGeometry *)geom
{
    // Return a symbol depending on the type of geometry that was passed in.
    AGSSymbol *symbol = nil;
    if ([geom isKindOfClass:[AGSPoint class]] ||
        [geom isKindOfClass:[AGSMultipoint class]])
    {
        symbol = [AGSSimpleMarkerSymbol simpleMarkerSymbolWithColor:[UIColor redColor]];
    }
    else if ([geom isKindOfClass:[AGSPolyline class]])
    {
        symbol = [AGSSimpleLineSymbol simpleLineSymbolWithColor:[UIColor redColor] width:2.0f];        
    }
    else if ([geom isKindOfClass:[AGSPolygon class]])
    {
        symbol = [AGSSimpleFillSymbol simpleFillSymbolWithColor:[UIColor redColor] outlineColor:[UIColor blueColor]];
    }
    else {
        NSLog(@"Unrecognized Geometry Class: %@", geom);
    }
    return symbol;
}

- (AGSGraphic *) __eqsGetDefaultGraphicForGeometry:(AGSGeometry *)geom
{  
    // Create a graphic with an appropriate symbol and attributes, given a geometry.
    AGSGraphic *g = [AGSGraphic graphicWithGeometry:geom
                                             symbol:[self __eqsGetDefaultSymbolForGeometry:geom]
                                         attributes:[NSMutableDictionary dictionaryWithObject:kEQSGraphicTag forKey:kEQSGraphicTagKey]
                               infoTemplateDelegate:nil];
    return g;
}

- (AGSGraphicsLayer *)__eqsGetAppropriateGraphicsLayerForGraphic:(AGSGraphic *)graphic
{
    AGSGeometry *geom = graphic.geometry;
    AGSGraphicsLayer *gLayer = nil;
    if ([geom isKindOfClass:[AGSPoint class]] ||
        [geom isKindOfClass:[AGSMultipoint class]])
    {
        gLayer = [self getGraphicsLayer:EQSGraphicsLayerTypePoint];
    }
    else if ([geom isKindOfClass:[AGSPolyline class]])
    {
        gLayer = [self getGraphicsLayer:EQSGraphicsLayerTypePolyline];
    }
    else if ([geom isKindOfClass:[AGSPolygon class]])
    {
        gLayer = [self getGraphicsLayer:EQSGraphicsLayerTypePolygon];
    }
    else {
        NSLog(@"Unrecognized Geometry Class: %@", geom);
    }
    return gLayer;
}

- (AGSGraphicsLayer *) __eqsAddGraphicToAppropriateGraphicsLayer:(AGSGraphic *)graphic
{
    // Figure out what type of geometry the graphic is, and add the graphic to the appropriate layer.
    if (graphic)
    {
        AGSGraphicsLayer *gLayer = [self __eqsGetAppropriateGraphicsLayerForGraphic:graphic];
        
        if (gLayer)
        {
            [gLayer addGraphic:graphic];
            [gLayer dataChanged];
        }
        
        return gLayer;
    }
    return nil;
}

- (NSArray *) __eqsGetArrayFromArguments:(NSNumber *)first arguments:(va_list)otherArgs
{
    // Just a helper function.
    NSMutableArray *result = [NSMutableArray array];
    for (NSNumber *nextNumber = first; nextNumber != nil; nextNumber = va_arg(otherArgs, NSNumber *))
    {
        [result addObject:nextNumber];
    }

    return result;
}
@end