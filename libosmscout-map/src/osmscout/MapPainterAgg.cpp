/*
  This source is part of the libosmscout-map library
  Copyright (C) 2011  Tim Teulings

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

#include <osmscout/MapPainterAgg.h>

#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>

#include <agg2/agg_conv_bspline.h>
#include <agg2/agg_conv_dash.h>
#include <agg2/agg_conv_segmentator.h>
#include <agg2/agg_conv_stroke.h>
#include <agg2/agg_path_storage.h>
#include <agg2/agg_trans_single_path.h>

#include <osmscout/util/Geometry.h>
#include <osmscout/util/String.h>

namespace osmscout {

  MapPainterAgg::MapPainterAgg()
  {
    // no code
  }

  MapPainterAgg::~MapPainterAgg()
  {
    // no code
    // TODO: Clean up fonts
  }

  void MapPainterAgg::SetFont(const MapParameter& parameter,
                              double size)
  {
    if (!fontEngine->load_font(parameter.GetFontName().c_str(),
                               0,
                               agg::glyph_ren_native_gray8)) {
      std::cout << "Cannot load font '" << parameter.GetFontName() << "'" << std::endl;
      return;

    }

    //fontEngine->resolution(72);
    fontEngine->width(size*parameter.GetFontSize());
    fontEngine->height(size*parameter.GetFontSize());
    fontEngine->hinting(true);
    fontEngine->flip_y(true);
  }

  void MapPainterAgg::SetOutlineFont(const MapParameter& parameter,
                                     double size)
  {
    if (!fontEngine->load_font(parameter.GetFontName().c_str(),
                               0,
                               agg::glyph_ren_outline)) {
      std::cout << "Cannot load font '" << parameter.GetFontName() << "'" << std::endl;
      return;

    }

    //fontEngine->resolution(72);
    fontEngine->width(size*parameter.GetFontSize());
    fontEngine->height(size*parameter.GetFontSize());
    fontEngine->hinting(true);
    fontEngine->flip_y(true);
  }

  void MapPainterAgg::GetTextDimension(const std::wstring& text,
                                       double& width,
                                       double& height)
  {

    width=0;
    height=fontEngine->height();

    for (size_t i=0; i<text.length(); i++) {
      const agg::glyph_cache* glyph=fontCacheManager->glyph(text[i]);

      if (glyph!=NULL) {
        width+=glyph->advance_x;
      }
    }
  }

  void MapPainterAgg::GetTextDimension(const MapParameter& parameter,
                                       double fontSize,
                                       const std::string& text,
                                       double& xOff,
                                       double& yOff,
                                       double& width,
                                       double& height)
  {
    std::wstring wideText(UTF8StringToWString(text));

    xOff=0;
    yOff=0;
    width=0;
    height=fontEngine->height();

    SetFont(parameter,fontSize);

    for (size_t i=0; i<wideText.length(); i++) {
      const agg::glyph_cache* glyph=fontCacheManager->glyph(wideText[i]);

      if (glyph!=NULL) {
        width+=glyph->advance_x;
      }
    }
  }

  void MapPainterAgg::DrawText(double x,
                               double y,
                               const std::wstring& text)
  {
    for (size_t i=0; i<text.length(); i++) {
      const agg::glyph_cache* glyph = fontCacheManager->glyph(text[i]);

      if (glyph!=NULL) {
        if (true) {
          fontCacheManager->add_kerning(&x, &y);
        }

        fontCacheManager->init_embedded_adaptors(glyph,x,y);

        switch (glyph->data_type) {
        default:
          break;
        case agg::glyph_data_mono:
          agg::render_scanlines(fontCacheManager->mono_adaptor(),
                                fontCacheManager->mono_scanline(),
                                *renderer_bin);
          break;

        case agg::glyph_data_gray8:
          agg::render_scanlines(fontCacheManager->gray8_adaptor(),
                                fontCacheManager->gray8_scanline(),
                                *renderer_aa);
          break;

        case agg::glyph_data_outline:
          rasterizer->reset();

          if(convTextContours->width() <= 0.01) {
            rasterizer->add_path(*convTextCurves);
          }
          else {
            rasterizer->add_path(*convTextContours);
          }
          agg::render_scanlines(*rasterizer,
                                *scanlineP8,
                                *renderer_aa);
          break;
        }

        // increment pen position
        x += glyph->advance_x;
        y += glyph->advance_y;
      }
    }
  }

  void MapPainterAgg::DrawOutlineText(double x,
                                      double y,
                                      const std::wstring& text,
                                      double width)
  {
    convTextContours->width(width);

    for (size_t i=0; i<text.length(); i++) {
      const agg::glyph_cache* glyph = fontCacheManager->glyph(text[i]);

      if (glyph!=NULL) {
        if (true) {
          fontCacheManager->add_kerning(&x, &y);
        }

        fontCacheManager->init_embedded_adaptors(glyph,x,y);

        switch (glyph->data_type) {
        default:
          break;
        case agg::glyph_data_mono:
          agg::render_scanlines(fontCacheManager->mono_adaptor(),
                                fontCacheManager->mono_scanline(),
                                *renderer_bin);
          break;
        case agg::glyph_data_gray8:
          agg::render_scanlines(fontCacheManager->gray8_adaptor(),
                                fontCacheManager->gray8_scanline(),
                                *renderer_aa);
          break;
        case agg::glyph_data_outline:
          rasterizer->reset();

          if(convTextContours->width() <= 0.01) {
            rasterizer->add_path(*convTextCurves);
          }
          else {
            rasterizer->add_path(*convTextContours);
          }
          agg::render_scanlines(*rasterizer,
                                *scanlineP8,
                                *renderer_aa);
          break;
        }

        // increment pen position
        x += glyph->advance_x;
        y += glyph->advance_y;
      }
    }
  }

  bool MapPainterAgg::HasIcon(const StyleConfig& styleConfig,
                             const MapParameter& parameter,
                             IconStyle& style)
  {
    if (style.GetId()==std::numeric_limits<size_t>::max()) {
      return false;
    }

    if (style.GetId()!=0) {
      return true;
    }

    std::string filename=std::string("../libosmscout/data/icons/14x14/standard/")+
                         style.GetIconName()+".png";

    //TODO

    return false;
  }

  bool MapPainterAgg::HasPattern(const StyleConfig& styleConfig,
                                 const MapParameter& parameter,
                                 PatternStyle& style)
  {
    if (style.GetId()==std::numeric_limits<size_t>::max()) {
      return false;
    }

    if (style.GetId()!=0) {
      return true;
    }

    std::string filename=std::string("../libosmscout/data/icons/14x14/standard/")+
                         style.GetPatternName()+".png";

    // TODO

    return false;
  }

  void MapPainterAgg::DrawLabel(const Projection& projection,
                               const MapParameter& parameter,
                               const Label& label)
  {
    double       r=label.style->GetTextR();
    double       g=label.style->GetTextG();
    double       b=label.style->GetTextB();
    std::wstring wideText(UTF8StringToWString(label.text));

    if (label.style->GetStyle()==LabelStyle::normal) {

      SetFont(parameter,
              label.fontSize);

      //renderer_bin->color(agg::rgba(r,g,b,a));
      renderer_aa->color(agg::rgba(r,g,b,label.alpha));

      DrawText(label.x,label.y+fontEngine->ascender(),wideText);
    }
    else if (label.style->GetStyle()==LabelStyle::emphasize) {
      SetOutlineFont(parameter,
                     label.fontSize);

      //renderer_bin->color(agg::rgba(r,g,b,a));
      renderer_aa->color(agg::rgba(1,1,1,label.alpha));

      DrawOutlineText(label.x,label.y+fontEngine->ascender(),wideText,2);

      SetFont(parameter,
              label.fontSize);

      //renderer_bin->color(agg::rgba(r,g,b,a));
      renderer_aa->color(agg::rgba(r,g,b,label.alpha));

      DrawText(label.x,label.y+fontEngine->ascender(),wideText);
    }
  }

  void MapPainterAgg::DrawPlateLabel(const Projection& projection,
                                     const MapParameter& parameter,
                                     const Label& label)
  {
    // TODO
  }

  void MapPainterAgg::DrawContourLabel(const Projection& projection,
                                      const MapParameter& parameter,
                                      const LabelStyle& style,
                                      const std::string& text,
                                      const TransPolygon& contour)
  {
    double       fontSize=style.GetSize();
    double       r=style.GetTextR();
    double       g=style.GetTextG();
    double       b=style.GetTextB();
    double       a=style.GetTextA();
    std::wstring wideText(UTF8StringToWString(text));

    SetOutlineFont(parameter,
                   fontSize);

    //renderer_bin->color(agg::rgba(r,g,b,a));
    renderer_aa->color(agg::rgba(r,g,b,a));

    agg::path_storage path;

    double length=0;
    double xo=0;
    double yo=0;

    if (contour.points[contour.GetStart()].x<contour.points[contour.GetEnd()].x) {
      for (size_t j=contour.GetStart(); j<=contour.GetEnd(); j++) {
        if (contour.points[j].draw) {
          if (j==contour.GetStart()) {
            path.move_to(contour.points[j].x,
                contour.points[j].y);
          }
          else {
            path.line_to(contour.points[j].x,
                         contour.points[j].y);
            length+=sqrt(pow(contour.points[j].x-xo,2)+
                         pow(contour.points[j].y-yo,2));
          }

          xo=contour.points[j].x;
          yo=contour.points[j].y;
        }
      }
    }
    else {
      for (size_t j=0; j<=contour.GetEnd()-contour.GetStart(); j++) {
        size_t idx=contour.GetEnd()-j;

        if (contour.points[idx].draw) {
          if (j==contour.GetStart()) {
            path.move_to(contour.points[idx].x,
                contour.points[idx].y);
          }
          else {
            path.line_to(contour.points[idx].x,
                         contour.points[idx].y);
            length+=sqrt(pow(contour.points[idx].x-xo,2)+
                         pow(contour.points[idx].y-yo,2));
          }

          xo=contour.points[idx].x;
          yo=contour.points[idx].y;
        }
      }
    }

    double width;
    double height;

    GetTextDimension(wideText,width,height);

    if (width>length) {
      return;
    }

    /*
    typedef agg::conv_bspline<agg::path_storage> conv_bspline_type;

    conv_bspline_type bspline(path);
    bspline.interpolation_step(1.0 / path.total_vertices());*/

    agg::trans_single_path tcurve;
    tcurve.add_path(path); // bspline

    typedef agg::conv_segmentator<AggTextCurveConverter> conv_font_segm_type;
    typedef agg::conv_transform<conv_font_segm_type,
    agg::trans_single_path>                              conv_font_trans_type;

    conv_font_segm_type  fsegm(*convTextCurves);
    conv_font_trans_type ftrans(fsegm, tcurve);

    fsegm.approximation_scale(3.0);

    double x=(length-width)/2;
    double y=-height/2+fontEngine->ascender();

    for (size_t i=0; i<wideText.length(); i++) {
      const agg::glyph_cache* glyph = fontCacheManager->glyph(wideText[i]);

      if (glyph!=NULL) {
        fontCacheManager->add_kerning(&x, &y);
        fontCacheManager->init_embedded_adaptors(glyph,x,y);

        if (glyph->data_type==agg::glyph_data_outline) {
          rasterizer->reset();
          rasterizer->add_path(ftrans);
          renderer_aa->color(agg::rgba(r,g,b,a));
          agg::render_scanlines(*rasterizer,
                                *scanlineP8,
                                *renderer_aa);
        }

        // increment pen position
        x += glyph->advance_x;
        y += glyph->advance_y;
      }
    }
  }

  void MapPainterAgg::DrawIcon(const IconStyle* style,
                              double x, double y)
  {
    assert(style->GetId()>0);
    assert(style->GetId()!=std::numeric_limits<size_t>::max());
    //assert(style->GetId()<=images.size());
    //assert(!images[style->GetId()-1].isNull());

    // TODO
  }

  void MapPainterAgg::DrawSymbol(const SymbolStyle* style, double x, double y)
  {
    // TODO
  }

  void MapPainterAgg::DrawPath(const Projection& projection,
                               const MapParameter& parameter,
                               double r,
                               double g,
                               double b,
                               double a,
                               double width,
                               const std::vector<double>& dash,
                               CapStyle startCap,
                               CapStyle endCap,
                               const TransPolygon& path)
  {
    agg::path_storage p;

    for (size_t i=polygon.GetStart(); i<=polygon.GetEnd(); i++) {
      if (polygon.points[i].draw) {
        if (i==polygon.GetStart()) {
          p.move_to(polygon.points[i].x,polygon.points[i].y);
        }
        else {
          p.line_to(polygon.points[i].x,polygon.points[i].y);
        }
      }
    }

    renderer_aa->color(agg::rgba(r,g,b,a));

    if (dash.empty()) {
      agg::conv_stroke<agg::path_storage> stroke(p);

      stroke.width(width);

      if (startCap==capRound &&
          endCap==capRound) {
        stroke.line_cap(agg::round_cap);
      }
      else {
        stroke.line_cap(agg::butt_cap);
      }

      rasterizer->add_path(stroke);

      agg::render_scanlines(*rasterizer,*scanlineP8,*renderer_aa);
    }
    else {
      agg::conv_dash<agg::path_storage>                    dasher(p);
      agg::conv_stroke<agg::conv_dash<agg::path_storage> > stroke(dasher);

      stroke.width(width);

      stroke.line_cap(agg::butt_cap);

      for (size_t i=0; i<dash.size(); i+=2) {
        dasher.add_dash(dash[i]*width,dash[i+1]*width);
      }

      rasterizer->add_path(stroke);

      agg::render_scanlines(*rasterizer,*scanlineP8,*renderer_aa);
    }

    // TODO: End point caps "dots"
  }

  void MapPainterAgg::DrawArea(const Projection& projection,
                              const MapParameter& parameter,
                              TypeId type,
                              const FillStyle& fillStyle,
                              const LineStyle* lineStyle,
                              const TransPolygon& area)
  {
    agg::path_storage path;

    for (size_t i=polygon.GetStart(); i<=polygon.GetEnd(); i++) {
      if (polygon.points[i].draw) {
        if (i==polygon.GetStart()) {
          path.move_to(polygon.points[i].x,polygon.points[i].y);
        }
        else {
          path.line_to(polygon.points[i].x,polygon.points[i].y);
        }
      }
    }

    path.close_polygon();

    renderer_aa->color(agg::rgba(fillStyle.GetFillR(),
                                 fillStyle.GetFillG(),
                                 fillStyle.GetFillB(),
                                 1));

    rasterizer->add_path(path);

    agg::render_scanlines(*rasterizer,*scanlineP8,*renderer_aa);

    if (lineStyle!=NULL) {
      DrawPath(projection,
               parameter,
               lineStyle->GetLineR(),
               lineStyle->GetLineG(),
               lineStyle->GetLineB(),
               lineStyle->GetLineA(),
               borderWidth[(size_t)type],
               lineStyle->GetDash(),
               capRound,
               capRound,
               area);
    }
  }

  void MapPainterAgg::DrawArea(const Projection& projection,
                              const MapParameter& parameter,
                              TypeId type,
                              const PatternStyle& patternStyle,
                              const LineStyle* lineStyle,
                              const TransPolygon& area)
  {
    // TODO
  }

  void MapPainterAgg::DrawArea(const FillStyle& style,
                              const MapParameter& parameter,
                              double x,
                              double y,
                              double width,
                              double height)
  {
    agg::path_storage path;

    path.move_to(x,y);
    path.line_to(x+width,y);
    path.line_to(x+width,y+height);
    path.line_to(x, y+height);
    path.close_polygon();

    renderer_aa->color(agg::rgba(style.GetFillR(),
                                 style.GetFillG(),
                                 style.GetFillB(),
                                 1));

    rasterizer->add_path(path);
    agg::render_scanlines(*rasterizer,*scanlineP8,*renderer_aa);
  }

  bool MapPainterAgg::DrawMap(const StyleConfig& styleConfig,
                             const Projection& projection,
                             const MapParameter& parameter,
                             const MapData& data,
                             AggPixelFormat* pf)
  {
    this->pf=pf;

    renderer_base=new AggRenderBase(*pf);
    rasterizer=new AggScanlineRasterizer();
    scanlineP8=new AggScanline();
    renderer_aa=new AggScanlineRendererAA(*renderer_base);
    renderer_bin=new AggScanlineRendererBin(*renderer_base);
    fontEngine=new AggFontEngine();
    fontCacheManager=new AggFontManager(*fontEngine);

    convTextCurves=new AggTextCurveConverter(fontCacheManager->path_adaptor());
    convTextCurves->approximation_scale(2.0);

    convTextContours= new AggTextContourConverter(*convTextCurves);

    Draw(styleConfig,
         projection,
         parameter,
         data);

    delete convTextCurves;
    delete convTextContours;
    delete fontEngine;
    delete fontCacheManager;
    delete renderer_bin;
    delete renderer_aa;
    delete scanlineP8;
    delete rasterizer;
    delete renderer_base;

    return true;
  }
}

