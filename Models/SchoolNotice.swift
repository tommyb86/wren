import Foundation
import SwiftData
import WrenCore

/// One stored news item from the school feed. Written once from the `all` feed
/// and thereafter enriched — labels from the topic feeds union on, and a notice
/// is never deleted because it dropped out of a feed's rolling window.
@Model
final class SchoolNotice {
    /// The numeric article id. The dedupe key.
    var guid: String = ""
    var title: String = ""
    /// Flattened text, for ranking and previews.
    var bodyText: String = ""
    /// Original body HTML, so the detail view can render paragraphs and bullets.
    var bodyHTML: String = ""
    var published: Date = Date.distantPast
    var category: String = ""
    /// Position in the feed as last seen; `<= 3` means pinned by the school.
    var feedPosition: Int = 0
    /// Topic-feed labels the school has attached. Only ever grows.
    var labels: [String] = []
    var imageHash: String = ""
    var firstSeen: Date = Date()
    var isRead: Bool = false

    init(
        guid: String = "",
        title: String = "",
        bodyText: String = "",
        bodyHTML: String = "",
        published: Date = .distantPast,
        category: String = "",
        feedPosition: Int = 0,
        labels: [String] = [],
        imageHash: String = "",
        firstSeen: Date = Date(),
        isRead: Bool = false
    ) {
        self.guid = guid
        self.title = title
        self.bodyText = bodyText
        self.bodyHTML = bodyHTML
        self.published = published
        self.category = category
        self.feedPosition = feedPosition
        self.labels = labels
        self.imageHash = imageHash
        self.firstSeen = firstSeen
        self.isRead = isRead
    }
}

extension SchoolNotice {
    convenience init(from item: SchoolFeedItem) {
        self.init(
            guid: item.guid,
            title: item.title,
            bodyText: item.bodyText,
            bodyHTML: item.bodyHTML,
            published: item.published ?? .distantPast,
            category: item.category,
            feedPosition: item.position,
            labels: item.labels,
            imageHash: item.imageHash,
            firstSeen: Date()
        )
    }

    var isPinned: Bool { feedPosition <= 3 }

    /// Bridge into WrenCore, which knows nothing about SwiftData.
    var feedItem: SchoolFeedItem {
        SchoolFeedItem(
            guid: guid,
            title: title,
            bodyText: bodyText,
            bodyHTML: bodyHTML,
            published: published == .distantPast ? nil : published,
            category: category,
            position: feedPosition,
            imageHash: imageHash,
            labels: labels
        )
    }

    /// Refreshes the mutable fields from a newly fetched item and unions any new
    /// labels. Never drops a label or overwrites `firstSeen`.
    func merge(_ item: SchoolFeedItem) {
        title = item.title
        bodyText = item.bodyText
        if !item.bodyHTML.isEmpty { bodyHTML = item.bodyHTML }
        if let published = item.published { self.published = published }
        category = item.category
        feedPosition = item.position
        if !item.imageHash.isEmpty { imageHash = item.imageHash }
        for label in item.labels where !labels.contains(label) {
            labels.append(label)
        }
    }
}
