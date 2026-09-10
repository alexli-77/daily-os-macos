import DailyOSCore
import Foundation

// The artifact index: `GET /api/artifacts`.
//
// The index is not a set of records the service authored — it is a listing of
// files that already exist in the user's own directories, produced by whatever
// wrote them and named however they were named. So nothing here refuses a row:
// an unrecognised `type`, a timestamp in a shape no formatter expects, a file
// whose extension the service never learned — each one degrades to something
// showable, because the alternative is a screen that hides files the user can
// see in Finder.

// MARK: - Wire types

struct ArtifactsResponseDTO: Decodable {
  let artifacts: [ArtifactDTO]
}

/// `ArtifactRecord` in the service's `src/storage/artifacts.ts`, minus the two
/// fields nothing on this side reads: `tags`, which no screen shows, and
/// `rel_path`, which is relative to the service's own checkout and so is the
/// wrong handle for a Mac app that opens files by absolute path.
struct ArtifactDTO: Decodable {
  let id: String
  /// Absolute path on disk. `Artifact` has nowhere to put this — see
  /// `DailyOSClient.artifacts()`.
  let path: String
  let name: String
  /// One of `markdown | text | json | log | image | pdf | binary` today. Kept as
  /// a `String` rather than an enum so that a kind added service-side arrives as
  /// an unknown word to be mapped, not as a decoding failure that empties the
  /// whole list.
  let type: String
  let size: Int
  /// The file's mtime: when the thing that produced it last wrote it.
  let mtime: String
  /// When the index first noticed the file. Only a fallback here — it says when
  /// the service looked, not when the work happened.
  let registeredAt: String?

  enum CodingKeys: String, CodingKey {
    case id, path, name, type, size, mtime
    case registeredAt = "registered_at"
  }
}

// MARK: - Mapping

extension ArtifactDTO {
  /// Seven service kinds into five domain cases.
  ///
  /// `text`, `log` and `binary` have no counterpart in `ArtifactType`, and they
  /// are not a rare edge: a real index on this machine is mostly `log` and
  /// One-to-one with the wire now that `ArtifactType` carries the service's
  /// full set. It used to be a table of stand-ins, and on a real index that
  /// renamed six rows out of seven.
  var domainType: ArtifactType {
    ArtifactType(rawValue: type) ?? .unknown
  }

  /// Newest-first ordering and the "生成于" row both read this.
  ///
  /// `CycleWireDate` rather than a local formatter: `mtime` carries fractional
  /// seconds (`2026-09-10T02:02:41.119Z`) and a plain `.iso8601` decode rejects
  /// exactly that shape. Falling through to the registration stamp and then to
  /// now keeps an odd row in the list at the top rather than dropping it or
  /// burying it in year one.
  var createdAt: Date {
    CycleWireDate.timestamp(mtime) ?? CycleWireDate.timestamp(registeredAt) ?? .now
  }
}

// MARK: - Client

extension DailyOSClient {
  /// The artifact index, newest first, with each file's location beside it.
  ///
  /// Two values rather than one because `Artifact` (in `DailyOSCore`) has no
  /// field for the absolute path, and widening a shared domain type is not a
  /// decision this file gets to make on its own. A parallel dictionary carries
  /// the path exactly as far as it has to go — to whoever wants to open the
  /// file — instead of introducing a second artifact type that every caller
  /// would then have to choose between. Giving `Artifact` a `path` is the
  /// better answer; when that lands, this returns a plain `[Artifact]`.
  ///
  public func artifacts() async throws -> [Artifact] {
    let response: ArtifactsResponseDTO = try await get("/api/artifacts")

    let rows = response.artifacts
      .map { (dto: $0, createdAt: $0.createdAt) }
      .sorted { $0.createdAt > $1.createdAt }

    var items: [Artifact] = []
    items.reserveCapacity(rows.count)

    for row in rows {
      items.append(
        Artifact(
          id: row.dto.id,
          name: row.dto.name,
          type: row.dto.domainType,
          byteSize: row.dto.size,
          createdAt: row.createdAt,
          // The record's `source` is the scan bucket the file came from
          // (`logs`, `outputs`, `manual`), not a workflow run — nothing in the
          // index links a file back to the run that wrote it, so the detail
          // screen's "来自运行" row stays absent rather than pointing at a run
          // id that does not exist.
          runId: nil,
          // The list endpoint carries no file contents, and reading seven files
          // to fill a preview nobody has opened is not a list operation.
          // `/api/artifacts` has no per-file read either; the service's preview
          // guard (`findArtifactById`) is reachable only from its own web
          // console, so there is currently no endpoint to fill this from.
          preview: nil,
          path: URL(filePath: row.dto.path)
        )
      )
    }

    return items
  }
}
