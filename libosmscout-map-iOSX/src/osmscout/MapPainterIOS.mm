/*
  This source is part of the libosmscout-map library
  Copyright (C) 2009  Tim Teulings, Vladimir Vyskocil

  This library is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2.1 of the License, or (at your option) any later version.

  This library is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with this library; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307  USA
*/

#import <osmscout/MapPainterIOS.h>

#include <cassert>
#include <iostream>
#include <limits>

#include <osmscout/util/Geometry.h>

#include <osmscout/private/Math.h>

#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC. Either turn on ARC for the project or use -fobjc-arc flag
#endif

namespace osmscout {
        
    MapPainterIOS::MapPainterIOS(const StyleConfigRef& styleConfig)
    : MapPainter(styleConfig, new CoordBufferImpl<Vertex2D>()),
    coordBuffer((CoordBufferImpl<Vertex2D>*)transBuffer.buffer)
    {
#if TARGET_OS_IPHONE
        contentScale = [[UIScreen mainScreen] scale];
#else
        contentScale = 1.0;
#endif
    }
        
    MapPainterIOS::~MapPainterIOS(){
        for(std::vector<Image>::const_iterator image=images.begin(); image<images.end();image++){
            CGImageRelease(*image);
        }
        for(std::vector<Image>::const_iterator image=patternImages.begin(); image<patternImages.end();image++){
            CGImageRelease(*image);
        }
    }
    
    void MapPainterIOS::Reset(){
        coordBuffer->Reset();
        delete [] coordBuffer->buffer;
    }
    
    Font *MapPainterIOS::GetFont(const Projection& projection,
                                 const MapParameter& parameter,
                                 double fontSize)
    {
        std::map<size_t,Font *>::const_iterator f;
        
        fontSize=fontSize*projection.ConvertWidthToPixel(parameter.GetFontSize());
        
        f=fonts.find(fontSize);
        
        if (f!=fonts.end()) {
            return f->second;
        }
        
        Font *font = [Font fontWithName:[NSString stringWithUTF8String: parameter.GetFontName().c_str()] size:fontSize];
        return fonts.insert(std::pair<size_t,Font *>(fontSize,font)).first->second;
    }

    
    /*
     * DrawMap()
     */
    bool MapPainterIOS::DrawMap(const StyleConfig& styleConfig,
                               const Projection& projection,
                               const MapParameter& parameter,
                               const MapData& data,
                               CGContextRef paintCG){

        cg = paintCG;
        if(contentScale!=1.0){
            CGContextScaleCTM(cg, 1/contentScale, 1/contentScale);
        }
        Draw(projection,
             parameter,
             data);
        

        for ( auto it = wayLabels.begin(); it != wayLabels.end(); ++it ) {
            delete it->second;
        }
        wayLabels.clear();

        return true;
    }

    /*
     * HasIcon()
     */
    bool MapPainterIOS::HasIcon(const StyleConfig& styleConfig,
                                const MapParameter& parameter,
                                IconStyle& style){
        if (style.GetIconId()==0) {
            return false;
        }
        
        size_t idx=style.GetIconId()-1;
        
        if (idx<images.size() &&
            images[idx]!=NULL) {

            return true;
        }
        
        for (std::list<std::string>::const_iterator path=parameter.GetIconPaths().begin();
             path!=parameter.GetIconPaths().end();
             ++path) {
            
            std::string filename=*path+style.GetIconName()+".png";
            //std::cout << "Trying to Load image " << filename << std::endl;
            
#if TARGET_OS_IPHONE
            UIImage *image = [[UIImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String: filename.c_str()]];
#else
            NSImage *image = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String: filename.c_str()]];
#endif
            if (image) {
#if TARGET_OS_IPHONE
                CGImageRef imgRef= [image CGImage];
#else
                CGImageRef imgRef= [image CGImageForProposedRect:NULL context:[NSGraphicsContext currentContext] hints:NULL];
#endif
                CGImageRetain(imgRef);
                if (idx>=images.size()) {
                    images.resize(idx+1, NULL);
                }
                
                images[idx]=imgRef;                
                //std::cout << "Loaded image '" << filename << "'" << std::endl;

                return true;
            }
        }
        
        std::cerr << "ERROR while loading image '" << style.GetIconName() << "'" << std::endl;
        style.SetIconId(0);
        
        return false;
}
    
    static void DrawPattern (void * info,CGContextRef cg){
        CGImageRef imgRef = (CGImageRef)info;
#if TARGET_OS_IPHONE
        CGAffineTransform transform = {1,0,0,-1,0,0};
        transform.ty = CGImageGetHeight(imgRef);
        CGContextConcatCTM(cg,transform);
#endif
        CGRect rect = CGRectMake(0, 0, CGImageGetWidth(imgRef), CGImageGetHeight(imgRef));
        CGContextDrawImage(cg, rect, imgRef);
    }
    
    static CGPatternCallbacks patternCallbacks = {
      0, &DrawPattern,NULL
    };
    
    /*
     * HasPattern()
     */
    bool MapPainterIOS::HasPattern(const MapParameter& parameter,
                                   const FillStyle& style){
        assert(style.HasPattern());
        
        // Was not able to load pattern
        if (style.GetPatternId()==0) {
            return false;
        }
        
        size_t idx=style.GetPatternId()-1;
        
        if (idx<patternImages.size() &&
            patternImages[idx]!=NULL) {
            
            return true;
        }
        
        for (std::list<std::string>::const_iterator path=parameter.GetPatternPaths().begin();
             path!=parameter.GetPatternPaths().end();
             ++path) {
            std::string filename=*path+style.GetPatternName()+".png";
            
#if TARGET_OS_IPHONE
            UIImage *image = [[UIImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String: filename.c_str()]];
#else
            NSImage *image = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String: filename.c_str()]];
#endif
            if (image) {
#if TARGET_OS_IPHONE
                CGImageRef imgRef= [image CGImage];
#else
                NSRect rect = CGRectMake(0, 0, 16, 16);
                NSImageRep *imageRep = [image bestRepresentationForRect:rect context:[NSGraphicsContext currentContext] hints:0];
                NSInteger imgWidth = [imageRep pixelsWide];
                NSInteger imgHeight = [imageRep pixelsHigh];
                rect = CGRectMake(0, 0, imgWidth, imgHeight);
                CGImageRef imgRef= [image CGImageForProposedRect:&rect context:[NSGraphicsContext currentContext] hints:NULL];
#endif
                CGImageRetain(imgRef);
                
                if (idx>=patternImages.size()) {
                    patternImages.resize(idx+1, NULL);
                }
                
                patternImages[idx]=imgRef;
                //std::cout << "Loaded image " << filename << " (" <<  imgWidth << "x" << imgHeight <<  ") => id " << style.GetPatternId() << std::endl;
                return true;
            }
        }
        
        std::cerr << "ERROR while loading icon file '" << style.GetPatternName() << "'" << std::endl;
        style.SetPatternId(std::numeric_limits<size_t>::max());
        
        return false;
    }
    
    /**
     * Returns the height of the font.
     */
    void MapPainterIOS::GetFontHeight(const Projection& projection,
                                      const MapParameter& parameter,
                                      double fontSize,
                                      double& height){
        Font *font = GetFont(projection,parameter,fontSize);
#if TARGET_OS_IPHONE
        CGSize size = [@"Aj" sizeWithFont:font];
#else
        NSRect stringBounds = [@"Aj" boundingRectWithSize:CGSizeMake(500, 50) options:NSStringDrawingUsesLineFragmentOrigin attributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]];
        CGSize size = stringBounds.size;
#endif
        height = size.height;
    }
    
    /*
     * GetTextDimension()
     */
    void MapPainterIOS::GetTextDimension(const Projection& projection,
                                         const MapParameter& parameter,
                                         double fontSize,
                                         const std::string& text,
                                         double& xOff,
                                         double& yOff,
                                         double& width,
                                         double& height){
        Font *font = GetFont(projection,parameter,fontSize);
        NSString *str = [NSString stringWithUTF8String:text.c_str()];
#if TARGET_OS_IPHONE
        CGSize size = [str sizeWithFont:font];
#else
        NSRect stringBounds = [str boundingRectWithSize:CGSizeMake(500, 50) options:NSStringDrawingUsesLineFragmentOrigin attributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]];
        CGSize size = stringBounds.size;
#endif
        xOff = 0;
        yOff = 0;
        width = size.width;
        height = size.height;
    }
 
    double MapPainterIOS::textLength(const Projection& projection, const MapParameter& parameter, double fontSize, std::string text){
        double xOff;
        double yOff;
        double width;
        double height;
        GetTextDimension(projection,parameter,fontSize,text,xOff,yOff,width,height);
        return width;
    }
    
    double MapPainterIOS::textHeight(const Projection& projection, const MapParameter& parameter, double fontSize, std::string text){
        double xOff;
        double yOff;
        double width;
        double height;
        GetTextDimension(projection, parameter,fontSize,text,xOff,yOff,width,height);
        return height;
    }
    
    /*
     * DrawLabel(const Projection& projection, const MapParameter& parameter, const LabelData& label)
     */
    void MapPainterIOS::DrawLabel(const Projection& projection,
                   const MapParameter& parameter,
                   const LabelData& label){
        
        if (dynamic_cast<const TextStyle*>(label.style.get())!=NULL) {
            if(label.y <= MapPainterIOS::yLabelMargin ||
               label.y >= projection.GetHeight() - MapPainterIOS::yLabelMargin){
                return;
            }
            
            const TextStyle* style=dynamic_cast<const TextStyle*>(label.style.get());
            double           r=style->GetTextColor().GetR();
            double           g=style->GetTextColor().GetG();
            double           b=style->GetTextColor().GetB();
            
            
            CGContextSaveGState(cg);
            CGContextSetTextDrawingMode(cg, kCGTextFill);
            Font *font = GetFont(projection, parameter, label.fontSize);
            NSString *str = [NSString stringWithCString:label.text.c_str() encoding:NSUTF8StringEncoding];
            //std::cout << "label : "<< label.text << " font size : " << label.fontSize << std::endl;
            
            if (style->GetStyle()==TextStyle::normal) {
                CGContextSetRGBFillColor(cg, r, g, b, label.alpha);
#if TARGET_OS_IPHONE
                [str drawAtPoint:CGPointMake(label.x, label.y) withFont:font];
#else
                NSColor *color = [NSColor colorWithSRGBRed:style->GetTextColor().GetR() green:style->GetTextColor().GetG() blue:style->GetTextColor().GetB() alpha:style->GetTextColor().GetA()];
                NSDictionary *attrsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:font,NSFontAttributeName,color,NSForegroundColorAttributeName, nil];
                [str drawAtPoint:CGPointMake(label.x, label.y) withAttributes:attrsDictionary];
                
#endif
            } else if (style->GetStyle()==TextStyle::emphasize) {
                CGContextSetRGBFillColor(cg, r, g, b, label.alpha);
                CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
                CGColorRef haloColor = CGColorCreate(colorSpace, (CGFloat[]){ 1, 1, 1, static_cast<CGFloat>(label.alpha) });
                CGContextSetShadowWithColor( cg, CGSizeMake( 0.0, 0.0 ), 2.0f, haloColor );
#if TARGET_OS_IPHONE
                [str drawAtPoint:CGPointMake(label.x, label.y) withFont:font];
                // L4C: Mehr Schatten
                CGContextSetShadowWithColor( cg, CGSizeMake( 0.0, 0.0 ), 3.0f, haloColor );
                [str drawAtPoint:CGPointMake(label.x, label.y) withFont:font];
#else
                NSColor *color = [NSColor colorWithSRGBRed:style->GetTextColor().GetR() green:style->GetTextColor().GetG() blue:style->GetTextColor().GetB() alpha:style->GetTextColor().GetA()];
                NSDictionary *attrsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:font,NSFontAttributeName,color,NSForegroundColorAttributeName, nil];
                [str drawAtPoint:CGPointMake(label.x, label.y) withAttributes:attrsDictionary];
#endif
                CGColorRelease(haloColor);
                CGColorSpaceRelease(colorSpace);
            }
            CGContextRestoreGState(cg);
        }
        
        else if (dynamic_cast<const ShieldStyle*>(label.style.get())!=NULL) {
            const ShieldStyle* style=dynamic_cast<const ShieldStyle*>(label.style.get());
            
            
            if(label.bx1 <= MapPainterIOS::plateLabelMargin ||
               label.by1 <= MapPainterIOS::plateLabelMargin ||
               label.bx2 >= projection.GetWidth() - MapPainterIOS::plateLabelMargin ||
               label.by2 >= projection.GetHeight() - MapPainterIOS::plateLabelMargin
               ){
                return;
            }
            CGContextSaveGState(cg);
            CGContextSetRGBFillColor(cg,
                                     style->GetBgColor().GetR(),
                                     style->GetBgColor().GetG(),
                                     style->GetBgColor().GetB(),
                                     1);
            CGContextSetRGBStrokeColor(cg,style->GetBorderColor().GetR(),
                                       style->GetBorderColor().GetG(),
                                       style->GetBorderColor().GetB(),
                                       style->GetBorderColor().GetA());
            CGContextAddRect(cg, CGRectMake(label.bx1,
                                            label.by1,
                                            label.bx2-label.bx1+1,
                                            label.by2-label.by1+1));
            CGContextDrawPath(cg, kCGPathFillStroke);
            
            CGContextAddRect(cg, CGRectMake(label.bx1+2,
                                            label.by1+2,
                                            label.bx2-label.bx1+1-4,
                                            label.by2-label.by1+1-4));
            CGContextDrawPath(cg, kCGPathStroke);
            
            
            Font *font = GetFont(projection, parameter, label.fontSize);
            NSString *str = [NSString stringWithUTF8String:label.text.c_str()];
#if TARGET_OS_IPHONE
            CGContextSetRGBFillColor(cg,style->GetTextColor().GetR(),
                                     style->GetTextColor().GetG(),
                                     style->GetTextColor().GetB(),
                                     style->GetTextColor().GetA());
            [str drawAtPoint:CGPointMake(label.x, label.y) withFont:font];
#else
            NSColor *color = [NSColor colorWithSRGBRed:style->GetTextColor().GetR() green:style->GetTextColor().GetG() blue:style->GetTextColor().GetB() alpha:style->GetTextColor().GetA()];
            NSDictionary *attrsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:font,NSFontAttributeName,color,NSForegroundColorAttributeName, nil];
            [str drawAtPoint:CGPointMake(label.x, label.y) withAttributes:attrsDictionary];
#endif
            CGContextRestoreGState(cg);
            
        }
    }
    
    double MapPainterIOS::pathLength(size_t transStart, size_t transEnd){
        double len = 0.0;
        double deltaX, deltaY;
        for(size_t j=transStart; j<transEnd; j++) {
            deltaX = coordBuffer->buffer[j].GetX() - coordBuffer->buffer[j+1].GetX();
            deltaY = coordBuffer->buffer[j].GetY() - coordBuffer->buffer[j+1].GetX();
            len += sqrt(deltaX*deltaX + deltaY*deltaY);
        }
        return len;
    }
    
    void MapPainterIOS::followPathInit(FollowPathHandle &hnd, Vertex2D &origin, size_t transStart, size_t transEnd,
                                       bool isClosed, bool keepOrientation) {
        hnd.i = 0;
        hnd.nVertex = transEnd - transStart;
        bool isReallyClosed = (coordBuffer->buffer[transStart] == coordBuffer->buffer[transEnd]);
        if(isClosed && !isReallyClosed){
            hnd.nVertex++;
            hnd.closeWay = true;
        } else {
            hnd.closeWay = false;
        }
        if(keepOrientation || coordBuffer->buffer[transStart].GetX()<coordBuffer->buffer[transEnd].GetX()){
            hnd.transStart = transStart;
            hnd.transEnd = transEnd;
        } else {
            hnd.transStart = transEnd;
            hnd.transEnd = transStart;
        }
        hnd.direction = (hnd.transStart < hnd.transEnd) ? 1 : -1;
        origin.Set(coordBuffer->buffer[hnd.transStart].GetX(), coordBuffer->buffer[hnd.transStart].GetY());
    }
    
    bool MapPainterIOS::followPath(FollowPathHandle &hnd, double l, Vertex2D &origin) {
        
        double x = origin.GetX();
        double y = origin.GetY();
        double x2,y2;
        double deltaX, deltaY, len, fracToGo;
        while(hnd.i < hnd.nVertex) {
            if(hnd.closeWay && hnd.nVertex - hnd.i == 1){
                x2 = coordBuffer->buffer[hnd.transStart].GetX();
                y2 = coordBuffer->buffer[hnd.transStart].GetY();
            } else {
                x2 = coordBuffer->buffer[hnd.transStart+(hnd.i+1)*hnd.direction].GetX();
                y2 = coordBuffer->buffer[hnd.transStart+(hnd.i+1)*hnd.direction].GetY();
            }
            deltaX = (x2 - x);
            deltaY = (y2 - y);
            len = sqrt(deltaX*deltaX + deltaY*deltaY);
            
            fracToGo = l/len;
            if(fracToGo <= 1.0) {
                origin.Set(x + deltaX*fracToGo,y + deltaY*fracToGo);
                return true;
            }
            
            //advance to next point on the path
            l -= len;
            x = x2;
            y = y2;
            hnd.i++;
        }
        return false;
    }

    void MapPainterIOS::DrawContourSymbol(const Projection& projection,
                                          const MapParameter& parameter,
                                          const Symbol& symbol,
                                          double space,
                                          /*bool isClosed,*/
                                          size_t transStart, size_t transEnd){
        
        
        double minX,minY,maxX,maxY;
        symbol.GetBoundingBox(minX,minY,maxX,maxY);
        
        double width=projection.ConvertWidthToPixel(maxX-minX);
        double height=projection.ConvertWidthToPixel(maxY-minY);
        bool isClosed = false;
        CGAffineTransform transform=CGAffineTransformMake(1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
        Vertex2D origin;
        double slope;
        double x1,y1,x2,y2,x3,y3;
        FollowPathHandle followPathHnd;
        followPathInit(followPathHnd, origin, transStart, transEnd, isClosed, true);
        if(!isClosed && !followPath(followPathHnd, space/2, origin)){
            return;
        }
        CGContextSaveGState(cg);
        bool loop = true;
        while (loop){
            x1 = origin.GetX();
            y1 = origin.GetY();
            loop = followPath(followPathHnd, width/2, origin);
            if(loop){
                x2 = origin.GetX();
                y2 = origin.GetY();
                if(loop){
                    loop = followPath(followPathHnd, width/2, origin);
                    x3 = origin.GetX();
                    y3 = origin.GetY();
                    slope = atan2(y3-y1,x3-x1);
                    CGContextSaveGState(cg);
                    CGContextTranslateCTM(cg, x2, y2);
                    CGAffineTransform ct = CGAffineTransformConcat(transform, CGAffineTransformMakeRotation(slope));
                    CGContextConcatCTM(cg, ct);
                    DrawSymbol(projection, parameter, symbol, 0, height/2);
                    CGContextRestoreGState(cg);
                    loop = followPath(followPathHnd, space, origin);
                }
            }
        }
        CGContextRestoreGState(cg);
    }

    static inline double distSq(const Vertex2D &v1, const Vertex2D &v2){
        double dx = v1.GetX() - v2.GetX();
        double dy = v1.GetY() - v2.GetY();
        return dx*dx+dy*dy;
    }
    
    /*
     * DrawContourLabel(const Projection& projection,
     *                  const MapParameter& parameter,
     *                  const PathTextStyle& style,
     *                  const std::string& text,
     *                  size_t transStart, size_t transEnd)
     */
    void MapPainterIOS::DrawContourLabel(const Projection& projection,
                                         const MapParameter& parameter,
                                         const PathTextStyle& style,
                                         const std::string& text,
                                         size_t transStart, size_t transEnd){
        Font *font = GetFont(projection, parameter, style.GetSize());

        Vertex2D charOrigin;
        FollowPathHandle followPathHnd;
        followPathInit(followPathHnd, charOrigin, transStart, transEnd, false, false);
        if(!followPath(followPathHnd, contourLabelMargin, charOrigin)){
            return;
        }
        
        // check if the same label has been drawn near this one
        Vertex2D textOrigin(charOrigin);
        auto its = wayLabels.equal_range(text);
        for (auto it = its.first; it != its.second; ++it) {
            if(distSq(textOrigin, *it->second) < MapPainterIOS::sameLabelMinDistanceSq){
                return;
            }
        }
        
        CGContextSaveGState(cg);
#if TARGET_OS_IPHONE
        CGContextSetTextDrawingMode(cg, kCGTextFill);
        CGContextSetLineWidth(cg, 1.0);
        CGContextSetRGBFillColor(cg, style.GetTextColor().GetR(), style.GetTextColor().GetG(), style.GetTextColor().GetB(), style.GetTextColor().GetA());
        CGContextSetRGBStrokeColor(cg, 1, 1, 1, 1);
        CGContextSetFont(cg, (__bridge CGFontRef)font);
#else
        NSColor *color = [NSColor colorWithSRGBRed:style.GetTextColor().GetR() green:style.GetTextColor().GetG() blue:style.GetTextColor().GetB() alpha:style.GetTextColor().GetA()];
        NSDictionary *attrsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:font,NSFontAttributeName,color,NSForegroundColorAttributeName, nil];
#endif
        
        NSString *nsText= [NSString stringWithCString:text.c_str() encoding:NSUTF8StringEncoding];
        double x1,y1,x2,y2,slope;
        NSUInteger charsCount = [nsText length];
        Vertex2D *coords = new Vertex2D[charsCount];
        double *slopes = new double[charsCount];
        double nww,nhh,xOff,yOff;
        int labelRepeatCount = 0;
        while(labelRepeatCount++ < labelRepeatMaxCount){
            int i = 0;
            while(i<charsCount){
                
                NSString *str = [nsText substringWithRange:NSMakeRange(i, 1)];
                
                GetTextDimension(projection, parameter,style.GetSize(), [str cStringUsingEncoding:NSUTF8StringEncoding], xOff, yOff, nww, nhh);
                x1 = charOrigin.GetX();
                y1 = charOrigin.GetY();
                if(!followPath(followPathHnd,nww, charOrigin)){
                    goto exit;
                }
                x2 = charOrigin.GetX();
                y2 = charOrigin.GetY();
                slope = atan2(y2-y1, x2-x1);
                if(i>0 && fabs(slope - slopes[i-1])>=M_PI_4){
                    i=0;
                    continue;
                }
                coords[i].Set(x1, y1);
                slopes[i] = slope;
                
                if(!followPath(followPathHnd, 2, charOrigin)){
                    goto exit;
                }
                i++;
            }
            CGAffineTransform ct;
            for(int i=0;i<charsCount;i++) {
                NSString *str = [nsText substringWithRange:NSMakeRange(i, 1)];
                CGContextSaveGState(cg);
                CGContextTranslateCTM(cg, coords[i].GetX(),coords[i].GetY());
                ct = CGAffineTransformMakeRotation(slopes[i]);
                CGContextConcatCTM(cg, ct);
#if TARGET_OS_IPHONE
                [str drawAtPoint:CGPointMake(0,-nhh/2) withFont:font];
#else
                [str drawAtPoint:CGPointMake(0,-nhh/2) withAttributes:attrsDictionary];
#endif
                CGContextRestoreGState(cg);
            }
            if(!followPath(followPathHnd, contourLabelSpace, charOrigin)){
                goto exit2;
            }
        }
    exit2:
        // insert this label with its start point in the map
        wayLabels.insert(WayLabelsMap::value_type(text,new Vertex2D(textOrigin)));
    exit:
        delete[] coords;
        delete[] slopes;
        CGContextRestoreGState(cg);
    }

    /*
     *
     * DrawIcon(const IconStyle* style,
     *          double x, double y)
     */
    void MapPainterIOS::DrawIcon(const IconStyle* style,
                  double x, double y){
        size_t idx=style->GetIconId()-1;
        
        assert(idx<images.size());
        assert(images[idx]);
        
        CGFloat w = CGImageGetWidth(images[idx]);
        CGFloat h = CGImageGetHeight(images[idx]);
        CGRect rect = CGRectMake(x-w/2, -h/2-y, w, h);
        CGContextSaveGState(cg);
        CGContextScaleCTM(cg, 1.0, -1.0);
        CGContextDrawImage(cg, rect, images[idx]);
        CGContextRestoreGState(cg);
    }
    
    /*
     * DrawSymbol(const Projection& projection,
     *            const MapParameter& parameter,
     *            const SymbolRef& symbol,
     *            double x, double y)
     */
    void MapPainterIOS::DrawSymbol(const Projection& projection,
                    const MapParameter& parameter,
                    const Symbol& symbol,
                    double x, double y){
        double minX;
        double minY;
        double maxX;
        double maxY;

        symbol.GetBoundingBox(minX,minY,maxX,maxY);
        
        CGContextSaveGState(cg);
        for (std::list<DrawPrimitiveRef>::const_iterator p=symbol.GetPrimitives().begin();
             p!=symbol.GetPrimitives().end();
             ++p) {
            FillStyleRef fillStyle=(*p)->GetFillStyle();
            
            SetFill(projection,
                          parameter,
                          *fillStyle);
  
            DrawPrimitive* primitive=p->get();
            double         centerX=maxX-minX;
            double         centerY=maxY-minY;
            
            if (dynamic_cast<PolygonPrimitive*>(primitive)!=NULL) {
                PolygonPrimitive* polygon=dynamic_cast<PolygonPrimitive*>(primitive);
                CGContextBeginPath(cg);
                for (std::list<Vertex2D>::const_iterator pixel=polygon->GetCoords().begin();
                     pixel!=polygon->GetCoords().end();
                     ++pixel) {
                    if (pixel==polygon->GetCoords().begin()) {
                        CGContextMoveToPoint(cg,x+projection.ConvertWidthToPixel(pixel->GetX()-centerX),
                                             y+projection.ConvertWidthToPixel(maxY-pixel->GetY()-centerY));
                    } else {
                        CGContextAddLineToPoint(cg,x+projection.ConvertWidthToPixel(pixel->GetX()-centerX),
                                                y+projection.ConvertWidthToPixel(maxY-pixel->GetY()-centerY));
                    }
                }
                
                CGContextDrawPath(cg, kCGPathFill);
            }
            else if (dynamic_cast<RectanglePrimitive*>(primitive)!=NULL) {
                RectanglePrimitive* rectangle=dynamic_cast<RectanglePrimitive*>(primitive);
                CGRect rect = CGRectMake(x+projection.ConvertWidthToPixel(rectangle->GetTopLeft().GetX()-centerX),
                                         y+projection.ConvertWidthToPixel(maxY-rectangle->GetTopLeft().GetY()-centerY),
                                         projection.ConvertWidthToPixel(rectangle->GetWidth()),
                                         projection.ConvertWidthToPixel(rectangle->GetHeight()));
                CGContextAddRect(cg,rect);
                CGContextDrawPath(cg, kCGPathFill);
            }
            else if (dynamic_cast<CirclePrimitive*>(primitive)!=NULL) {
                CirclePrimitive* circle=dynamic_cast<CirclePrimitive*>(primitive);
                CGRect rect = CGRectMake(x+projection.ConvertWidthToPixel(circle->GetCenter().GetX()-centerX),
                                         y+projection.ConvertWidthToPixel(maxY-circle->GetCenter().GetY()-centerY),
                                         projection.ConvertWidthToPixel(circle->GetRadius()),
                                         projection.ConvertWidthToPixel(circle->GetRadius()));
                CGContextAddEllipseInRect(cg, rect);
                CGContextDrawPath(cg, kCGPathFill);
            }
        }
        CGContextRestoreGState(cg);
    }
    
    /*
     * DrawPath(const Projection& projection,
     *          const MapParameter& parameter,
     *          const Color& color,
     *          double width,
     *          const std::vector<double>& dash,
     *          CapStyle startCap,
     *          CapStyle endCap,
     *          size_t transStart, size_t transEnd)
     */
    void MapPainterIOS::DrawPath(const Projection& projection,
                  const MapParameter& parameter,
                  const Color& color,
                  double width,
                  const std::vector<double>& dash,
                  LineStyle::CapStyle startCap,
                  LineStyle::CapStyle endCap,
                  size_t transStart, size_t transEnd){
        
        CGContextSaveGState(cg);
        CGContextSetRGBStrokeColor(cg, color.GetR(), color.GetG(), color.GetB(), color.GetA());
        CGContextSetLineWidth(cg, width);
        CGContextSetLineJoin(cg, kCGLineJoinRound);

        if (dash.empty()) {
            CGContextSetLineDash(cg, 0.0, NULL, 0);
        } else {
            CGFloat *dashes = (CGFloat *)malloc(sizeof(CGFloat)*dash.size());
            for (size_t i=0; i<dash.size(); i++) {
                dashes[i] = dash[i]*width;
            }
            CGContextSetLineDash(cg, 0.0, dashes, dash.size());
            free(dashes); dashes = NULL;
            CGContextSetLineCap(cg, kCGLineCapButt);
        }
        CGContextBeginPath(cg);
        CGContextMoveToPoint(cg,coordBuffer->buffer[transStart].GetX(),coordBuffer->buffer[transStart].GetY());
        for (size_t i=transStart+1; i<=transEnd; i++) {
            CGContextAddLineToPoint (cg,coordBuffer->buffer[i].GetX(),coordBuffer->buffer[i].GetY());
        }
        CGContextStrokePath(cg);
        if (startCap==LineStyle::capRound) {
            CGContextSetRGBFillColor(cg, color.GetR(), color.GetG(), color.GetB(), color.GetA());
            CGContextFillEllipseInRect(cg, CGRectMake(coordBuffer->buffer[transStart].GetX()-width/2,
                                                     coordBuffer->buffer[transStart].GetY()-width/2,
                                                     width,width));
        }
        if (endCap==LineStyle::capRound) {
            CGContextSetRGBFillColor(cg, color.GetR(), color.GetG(), color.GetB(), color.GetA());
            CGContextFillEllipseInRect(cg, CGRectMake(coordBuffer->buffer[transEnd].GetX()-width/2,
                                                     coordBuffer->buffer[transEnd].GetY()-width/2,
                                                     width,width));
        }
        CGContextRestoreGState(cg);
    }
        
    /*
     * SetFill(const Projection& projection,
     *          const MapParameter& parameter,
     *          const FillStyle& fillStyle)
     */
    void MapPainterIOS::SetFill(const Projection& projection,
                                const MapParameter& parameter,
                                const FillStyle& fillStyle,
                                CGFloat xOffset, CGFloat yOffset) {
        
        double borderWidth=projection.ConvertWidthToPixel(fillStyle.GetBorderWidth());

        if (fillStyle.HasPattern() &&
            projection.GetMagnification()>=fillStyle.GetPatternMinMag() &&
            HasPattern(parameter,fillStyle)) {
            CGColorSpaceRef sp = CGColorSpaceCreatePattern(NULL);
            CGContextSetFillColorSpace (cg, sp);
            CGColorSpaceRelease (sp);
            CGFloat components = 1.0;
            size_t patternIndex = fillStyle.GetPatternId()-1;
            CGFloat imgWidth = CGImageGetWidth(patternImages[patternIndex]);
            CGFloat imgHeight = CGImageGetHeight(patternImages[patternIndex]);
            xOffset = remainder(xOffset/2, imgWidth);
            yOffset = remainder(yOffset/2, imgHeight);
            CGPatternRef pattern = CGPatternCreate(patternImages[patternIndex], CGRectMake(0,0, imgWidth, imgHeight), CGAffineTransformTranslate(CGAffineTransformIdentity, xOffset, yOffset), imgWidth, imgHeight, kCGPatternTilingNoDistortion, true, &patternCallbacks);
            CGContextSetFillPattern(cg, pattern, &components);
            CGPatternRelease(pattern);
        } else if (fillStyle.GetFillColor().IsVisible()) {

            CGContextSetRGBFillColor(cg, fillStyle.GetFillColor().GetR(), fillStyle.GetFillColor().GetG(),
                                     fillStyle.GetFillColor().GetB(), fillStyle.GetFillColor().GetA());
        } else {
            CGContextSetRGBFillColor(cg,0,0,0,0);
        }
        
        if (borderWidth>=parameter.GetLineMinWidthPixel()) {
            CGContextSetRGBStrokeColor(cg,fillStyle.GetBorderColor().GetR(),
                                          fillStyle.GetBorderColor().GetG(),
                                          fillStyle.GetBorderColor().GetB(),
                                          fillStyle.GetBorderColor().GetA());
            CGContextSetLineWidth(cg, borderWidth);
            
            if (fillStyle.GetBorderDash().empty()) {
                CGContextSetLineDash(cg, 0.0, NULL, 0);
            }
            else {
                CGFloat *dashes = (CGFloat *)malloc(sizeof(CGFloat)*fillStyle.GetBorderDash().size());
                for (size_t i=0; i<fillStyle.GetBorderDash().size(); i++) {
                    dashes[i] = fillStyle.GetBorderDash()[i]*borderWidth;
                }
                CGContextSetLineDash(cg, 0.0, dashes, fillStyle.GetBorderDash().size());
                free(dashes); dashes = NULL;
                CGContextSetLineCap(cg, kCGLineCapButt);
            }
        }
        else {
            CGContextSetRGBStrokeColor(cg,0,0,0,0);
        }
    }
    
    /*
     * SetPen(const LineStyle& style,
     *        double lineWidth)
     */
    void MapPainterIOS::SetPen(const LineStyle& style,
                              double lineWidth) {
        CGContextSetRGBStrokeColor(cg,style.GetLineColor().GetR(),
                                      style.GetLineColor().GetG(),
                                      style.GetLineColor().GetB(),
                                      style.GetLineColor().GetA());
        CGContextSetLineWidth(cg,lineWidth);
        
        if (style.GetDash().empty()) {
            CGContextSetLineDash(cg, 0.0, NULL, 0);
            CGContextSetLineCap(cg, kCGLineCapRound);
        }
        else {
            CGFloat *dashes = (CGFloat *)malloc(sizeof(CGFloat)*style.GetDash().size());
            for (size_t i=0; i<style.GetDash().size(); i++) {
                dashes[i] = style.GetDash()[i]*lineWidth;
            }
            CGContextSetLineDash(cg, 0.0, dashes, style.GetDash().size());
            free(dashes); dashes = NULL;
            CGContextSetLineCap(cg, kCGLineCapButt);
        }

    }

    
    /*
     * DrawArea(const Projection& projection,
     *          const MapParameter& parameter,
     *          const AreaData& area)
     */
    void MapPainterIOS::DrawArea(const Projection& projection,
                                const MapParameter& parameter,
                                const MapPainter::AreaData& area)
    {
        CGContextSaveGState(cg);
        CGContextBeginPath(cg);
        CGContextMoveToPoint(cg,coordBuffer->buffer[area.transStart].GetX(),
                    coordBuffer->buffer[area.transStart].GetY());
        for (size_t i=area.transStart+1; i<=area.transEnd; i++) {
            CGContextAddLineToPoint(cg,coordBuffer->buffer[i].GetX(),
                        coordBuffer->buffer[i].GetY());
        }
        CGContextAddLineToPoint(cg,coordBuffer->buffer[area.transStart].GetX(),
                                coordBuffer->buffer[area.transStart].GetY());
        
        if (!area.clippings.empty()) {
            for (std::list<PolyData>::const_iterator c=area.clippings.begin();
                 c!=area.clippings.end();
                 c++) {
                const PolyData& data=*c;
                
                CGContextMoveToPoint(cg,coordBuffer->buffer[data.transStart].GetX(),
                            coordBuffer->buffer[data.transStart].GetY());
                for (size_t i=data.transStart+1; i<=data.transEnd; i++) {
                    CGContextAddLineToPoint(cg,coordBuffer->buffer[i].GetX(),
                                coordBuffer->buffer[i].GetY());
                }
                CGContextAddLineToPoint(cg,coordBuffer->buffer[data.transStart].GetX(),
                                        coordBuffer->buffer[data.transStart].GetY());
            }
        }
        
        SetFill(projection, parameter, *area.fillStyle,
                coordBuffer->buffer[area.transStart].GetX(), coordBuffer->buffer[area.transStart].GetY());
        
        CGContextDrawPath(cg,  kCGPathEOFillStroke);
        CGContextRestoreGState(cg);
    }

    
    /*
     * DrawGround(const Projection& projection,
     *            const MapParameter& parameter,
     *            const FillStyle& style)
     */
    void MapPainterIOS::DrawGround(const Projection& projection,
                                   const MapParameter& parameter,
                                   const FillStyle& style){
        CGContextSaveGState(cg);
        CGContextBeginPath(cg);
        const Color &borderColor = style.GetBorderColor();
        CGContextSetRGBStrokeColor(cg, borderColor.GetR(), borderColor.GetG(), borderColor.GetB(), borderColor.GetA());
        const Color &fillColor = style.GetFillColor();
        CGContextSetRGBFillColor(cg, fillColor.GetR(), fillColor.GetG(), fillColor.GetB(), fillColor.GetA());
        CGContextAddRect(cg, CGRectMake(0,0,projection.GetWidth(),projection.GetHeight()));
        CGContextDrawPath(cg, kCGPathFillStroke);
        CGContextRestoreGState(cg);
    }
    
}
