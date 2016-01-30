#ifndef OSMSCOUT_AREAAREAINDEX_H
#define OSMSCOUT_AREAAREAINDEX_H

/*
  This source is part of the libosmscout library
  Copyright (C) 2010  Tim Teulings

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

#include <memory>
#include <mutex>
#include <vector>

#include <osmscout/DataFile.h>

#include <osmscout/util/Cache.h>
#include <osmscout/util/Geometry.h>
#include <osmscout/util/FileScanner.h>

namespace osmscout {

  /**
    \ingroup Database

    AreaAreaIndex allows you to find areas in
    a given region.

    For areas result can be limited by the maximum level (which in turn
    defines the minimum size of the resulting areas since an area in a given
    level must fit into the cell size (but can cross cell borders)) and the
    maximum number of areas found.

    Internally the index is implemented as quadtree. As a result each index entry
    has 4 children (besides entries in the lowest level).
    */
  class OSMSCOUT_API AreaAreaIndex
  {
  public:
    static const char* AREA_AREA_IDX;

  private:
    /**
      Data structure for every index cell of our index.
      */
    struct IndexCell
    {
      FileOffset children[4]; //!< File index of each of the four children, or 0 if there is no child
      FileOffset data;        //!< The file index at which the data payload starts
    };

    typedef Cache<FileOffset,IndexCell> IndexCache;

    struct IndexCacheValueSizer : public IndexCache::ValueSizer
    {
      size_t GetSize(const IndexCell& value) const
      {
        size_t memory=0;

        memory+=sizeof(value);

        return memory;
      }
    };

    struct CellRef
    {
      FileOffset offset;
      size_t     x;
      size_t     y;

      CellRef(FileOffset offset,
              size_t x,
              size_t y)
      : offset(offset),
        x(x),
        y(y)
      {
        // no code
      }
    };

  private:
    std::string           datafilename;   //!< Full path and name of the data file
    mutable FileScanner   scanner;        //!< Scanner instance for reading this file

    uint32_t              maxLevel;       //!< Maximum level in index
    FileOffset            topLevelOffset; //!< File offset of the top level index entry

    mutable IndexCache    indexCache;     //!< Cached map of all index entries by file offset

    mutable std::mutex    lookupMutex;

  private:
    bool GetIndexCell(uint32_t level,
                      FileOffset offset,
                      IndexCell& indexCell,
                      FileOffset& dataOffset) const;

    bool ReadCellData(const TypeConfig& typeConfig,
                      const TypeInfoSet& types,
                      FileOffset dataOffset,
                      std::vector<DataBlockSpan>& spans) const;

    void PushCellsForNextLevel(double minlon,
                               double minlat,
                               double maxlon,
                               double maxlat,
                               const IndexCell & cellIndexData,
                               const CellDimension& cellDimension,
                               size_t cx,
                               size_t cy,
                               std::vector<CellRef>& nextCellRefs) const;

  public:
    AreaAreaIndex(size_t cacheSize);

    void Close();
    bool Open(const std::string& path);

    inline bool IsOpen() const
    {
      return scanner.IsOpen();
    }

    bool GetAreasInArea(const TypeConfig& typeConfig,
                        const GeoBox& boundingBox,
                        size_t maxLevel,
                        const TypeInfoSet& types,
                        std::vector<DataBlockSpan>& spans,
                        TypeInfoSet& loadedTypes) const;

    void DumpStatistics();
  };

  typedef std::shared_ptr<AreaAreaIndex> AreaAreaIndexRef;
}

#endif
