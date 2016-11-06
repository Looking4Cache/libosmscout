/*
  This source is part of the libosmscout-map library
  Copyright (C) 2016  Tim Teulings

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

#include <osmscout/LabelLayouter.h>

namespace osmscout {

  LabelData::LabelData()
  {
    // no code
  }

  LabelData::~LabelData()
  {
    // no code
  }

  LabelLayouter::LabelLayouter()
  {
    // no code
  }

  LabelLayouter::~LabelLayouter()
  {
    // no code
  }

  void LabelLayouter::DeleteEventsForLabel(const std::set<LabelEvent>::iterator& eventRef)
  {
    LabelEvent searchEventTop;
    LabelEvent searchEventBottom;

    searchEventTop.y=eventRef->label->by1;
    searchEventTop.x=eventRef->label->bx1;

    searchEventBottom.y=eventRef->label->by2;
    searchEventBottom.x=eventRef->label->bx1;

    std::set<LabelEvent>::iterator event;

    event=events.find(searchEventTop);

    assert(event!=events.end());

    /*
    std::cout << "Removing event: ";
    std::cout << event->label->text << " ";
    std::cout << event->x << "," << event->y << " | ";
    std::cout << event->label->bx1 << " - " << event->label->bx2 << ", "  << event->label->by1 << " - " << event->label->by2 << std::endl;*/

    events.erase(event);

    event=events.find(searchEventBottom);

    assert(event!=events.end());

    /*
    std::cout << "Removing event: ";
    std::cout << event->label->text << " ";
    std::cout << event->x << "," << event->y << " | ";
    std::cout << event->label->bx1 << " - " << event->label->bx2 << ", "  << event->label->by1 << " - " << event->label->by2 << std::endl;*/

    events.erase(event);
  }

  bool LabelLayouter::Intersects(const LabelData& first, const LabelData& second) const
  {
    if (dynamic_cast<ShieldStyle*>(first.style.get())!=NULL &&
        dynamic_cast<ShieldStyle*>(second.style.get())!=NULL) {
      double horizLabelSpace=shieldLabelSpace;
      double vertLabelSpace=shieldLabelSpace;

      double hx1;
      double hx2;
      double hy1;
      double hy2;

      hx1=first.bx1-horizLabelSpace;
      hx2=first.bx2+horizLabelSpace;
      hy1=first.by1-vertLabelSpace;
      hy2=first.by2+vertLabelSpace;

      if (hx1>=second.bx2 ||
          hx2<=second.bx1 ||
          hy1>=second.by2 ||
          hy2<=second.by1) {
        return false;
      }

      if (first.text==second.text) {
        double horizLabelSpace=sameLabelSpace;
        double vertLabelSpace=sameLabelSpace;

        double hx1;
        double hx2;
        double hy1;
        double hy2;

        hx1=first.bx1-horizLabelSpace;
        hx2=first.bx2+horizLabelSpace;
        hy1=first.by1-vertLabelSpace;
        hy2=first.by2+vertLabelSpace;

        if (hx1>=second.bx2 ||
            hx2<=second.bx1 ||
            hy1>=second.by2 ||
            hy2<=second.by1) {
          return false;
        }
      }
    }
    else {
      double horizLabelSpace=labelSpace;
      double vertLabelSpace=labelSpace;

      double hx1;
      double hx2;
      double hy1;
      double hy2;

      hx1=first.bx1-horizLabelSpace;
      hx2=first.bx2+horizLabelSpace;
      hy1=first.by1-vertLabelSpace;
      hy2=first.by2+vertLabelSpace;

      if (hx1>=second.bx2 ||
          hx2<=second.bx1 ||
          hy1>=second.by2 ||
          hy2<=second.by1) {
        return false;
      }
    }

    return true;
  }

  void LabelLayouter::Initialize(const Projection& projection,
                                 const MapParameter& parameter)
  {
    labels.clear();
    events.clear();

    width=projection.GetWidth();
    height=projection.GetHeight();

    labelSpace=projection.ConvertWidthToPixel(parameter.GetLabelSpace());
    shieldLabelSpace=projection.ConvertWidthToPixel(parameter.GetPlateLabelSpace());
    sameLabelSpace=projection.ConvertWidthToPixel(parameter.GetSameLabelSpace());

    maxSpace=0.0;
    maxSpace=std::max(maxSpace,labelSpace);
    maxSpace=std::max(maxSpace,shieldLabelSpace);
    maxSpace=std::max(maxSpace,sameLabelSpace);
  }

  bool LabelLayouter::Placelabel(const LabelData& label,
                                 LabelDataRef& labelRef)
  {
    LabelEvent searchEvent;

      if (label.bx2<0 || label.bx1>=width) {
      return false;
    }

    if (label.by2<0 || label.by1>=height) {
      return false;
    }

    searchEvent.y=label.by1-maxSpace;
    searchEvent.x=label.bx1;

    std::set<LabelEvent>::iterator event=events.lower_bound(searchEvent);

    /*
    std::cout << "--- Placing: ";
    std::cout << label.text << " ";
    std::cout << label.bx1 << " - " << label.bx2 << ", "  << label.by1 << " - " << label.by2;
    std::cout << std::endl;

    for (const auto& ev ent : events) {
      std::cout << "Event: ";
      std::cout << event.label->text << " ";
      std::cout << event.x << "," << event.y << " | ";
      std::cout << event.label->bx1 << " - " << event.label->bx2 << ", "  << event.label->by1 << " - " << event.label->by2 << std::endl;
    }*/

    while (event!=events.end() &&
           label.by2+maxSpace>=event->y) {
      /*
      std::cout << event->label->text << " ";
      std::cout << event->x << "," << event->y << " | ";
      std::cout << event->label->bx1 << " - " << event->label->bx2 << ", "  << event->label->by1 << " - " << event->label->by2 << std::endl;*/
      if (Intersects(*event->label,label)) {
        if (label.priority<event->label->priority) {
          LabelDataRef oldLabel=event->label;

          //std::cout << "DROPPING lower prio " << event->label->text << " " << label.priority << " vs. " << event->label->priority << std::endl;
          DeleteEventsForLabel(event);
          labels.erase(oldLabel);

          // Restart the search :-/
          event=events.lower_bound(searchEvent);
        }
        else if (label.priority>event->label->priority) {
          LabelDataRef oldLabel=event->label;

          //std::cout << "DROPPING same prio and exit " << event->label->text << " " << label.priority << " vs. " << event->label->priority << std::endl;
          DeleteEventsForLabel(event);
          labels.erase(oldLabel);

          return false;
        }
        else {
          //std::cout << "CANCEL since higher prio " << event->label->text << " " << label.priority << " vs. " << event->label->priority << std::endl;
          return false;
        }
      }
      else {
        //std::cout << "IGNORING " << event->label->text << std::endl;
        event++;
      }
    }

    //std::cout << "INSERT" << std::endl;

    labels.push_front(label);
    labelRef=labels.begin();

    LabelEvent insertEvent;

    insertEvent.x=label.bx1;
    insertEvent.label=labelRef;

    insertEvent.y=label.by1;

    events.insert(insertEvent);

    insertEvent.y=label.by2;

    events.insert(insertEvent);

    return true;
  }
}
