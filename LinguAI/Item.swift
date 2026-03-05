//
//  Item.swift
//  LinguAI
//
//  Created by Domagoj Poljancic on 05.03.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
