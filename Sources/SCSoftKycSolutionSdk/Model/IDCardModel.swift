//
//  IDCardModel.swift
//  DigitalBankingGitPrivate
//
//  Created by Dijital Bankacılık on 17.09.2020.
//  Copyright © 2020 Ziraat Teknoloji. All rights reserved.
//

import Foundation
import UIKit

struct IDCardModel {
    
    var documentImage: UIImage = UIImage()
    var documentType: String = ""
    var countryCode: String = ""
    var surnames: String = ""
    var givenNames: String = ""
    var documentNumber: String = ""
    var nationality: String = ""
    var birthDate: Date? = Date()
    var gender: String = ""
    var expiryDate: Date? = Date()
    var personalNumber: String = ""
    
    
    init(documentNumber: String, birthDate: Date, expiryDate: Date) {
        self.documentNumber = documentNumber
        self.birthDate = birthDate
        self.expiryDate = expiryDate
    }
    
}
