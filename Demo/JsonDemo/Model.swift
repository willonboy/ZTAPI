//
//  Model.swift
//  JsonDemo
//
//  Copyright (c) 2026 trojanzhang. All rights reserved.
//
//  This file is part of ZTAPI.
//
//  ZTAPI is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ZTAPI is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with ZTAPI. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

#if canImport(ZTJSON)
import SwiftyJSON
import ZTJSON

let js = """
[
  {
    "id": 1,
    "name": "Leanne Graham",
    "username": "Bret",
    "email": "Sincere@april.biz",
    "address": {
      "street": "Kulas Light",
      "suite": "Apt. 556",
      "city": "Gwenborough",
      "zipcode": "92998-3874",
      "geo": {
        "lat": "-37.3159",
        "lng": "81.1496"
      }
    },
    "phone": "1-770-736-8031 x56442",
    "website": "hildegard.org",
    "company": {
      "name": "Romaguera-Crona",
      "catchPhrase": "Multi-layered client-server neural-net",
      "bs": "harness real-time e-markets"
    }
  },
  {
    "id": 2,
    "name": "Ervin Howell",
    "username": "Antonette",
    "email": "Shanna@melissa.tv",
    "address": {
      "street": "Victor Plains",
      "suite": "Suite 879",
      "city": "Wisokyburgh",
      "zipcode": "90566-7771",
      "geo": {
        "lat": "-43.9509",
        "lng": "-34.4618"
      }
    },
    "phone": "010-692-6593 x09125",
    "website": "anastasia.net",
    "company": {
      "name": "Deckow-Crist",
      "catchPhrase": "Proactive didactic contingency",
      "bs": "synergize scalable supply-chains"
    }
  },
  {
    "id": 3,
    "name": "Clementine Bauch",
    "username": "Samantha",
    "email": "Nathan@yesenia.net",
    "address": {
      "street": "Douglas Extension",
      "suite": "Suite 847",
      "city": "McKenziehaven",
      "zipcode": "59590-4157",
      "geo": {
        "lat": "-68.6102",
        "lng": "-47.0653"
      }
    },
    "phone": "1-463-123-4447",
    "website": "ramiro.info",
    "company": {
      "name": "Romaguera-Jacobson",
      "catchPhrase": "Face to face bifurcated interface",
      "bs": "e-enable strategic applications"
    }
  },
  {
    "id": 4,
    "name": "Patricia Lebsack",
    "username": "Karianne",
    "email": "Julianne.OConner@kory.org",
    "address": {
      "street": "Hoeger Mall",
      "suite": "Apt. 692",
      "city": "South Elvis",
      "zipcode": "53919-4257",
      "geo": {
        "lat": "29.4572",
        "lng": "-164.2990"
      }
    },
    "phone": "493-170-9623 x156",
    "website": "kale.biz",
    "company": {
      "name": "Robel-Corkery",
      "catchPhrase": "Multi-tiered zero tolerance productivity",
      "bs": "transition cutting-edge web services"
    }
  },
  {
    "id": 5,
    "name": "Chelsey Dietrich",
    "username": "Kamren",
    "email": "Lucio_Hettinger@annie.ca",
    "address": {
      "street": "Skiles Walks",
      "suite": "Suite 351",
      "city": "Roscoeview",
      "zipcode": "33263",
      "geo": {
        "lat": "-31.8129",
        "lng": "62.5342"
      }
    },
    "phone": "(254)954-1289",
    "website": "demarco.info",
    "company": {
      "name": "Keebler LLC",
      "catchPhrase": "User-centric fault-tolerant solution",
      "bs": "revolutionize end-to-end systems"
    }
  },
  {
    "id": 6,
    "name": "Mrs. Dennis Schulist",
    "username": "Leopoldo_Corkery",
    "email": "Karley_Dach@jasper.info",
    "address": {
      "street": "Norberto Crossing",
      "suite": "Apt. 950",
      "city": "South Christy",
      "zipcode": "23505-1337",
      "geo": {
        "lat": "-71.4197",
        "lng": "71.7478"
      }
    },
    "phone": "1-477-935-8478 x6430",
    "website": "ola.org",
    "company": {
      "name": "Considine-Lockman",
      "catchPhrase": "Synchronised bottom-line interface",
      "bs": "e-enable innovative applications"
    }
  },
  {
    "id": 7,
    "name": "Kurtis Weissnat",
    "username": "Elwyn.Skiles",
    "email": "Telly.Hoeger@billy.biz",
    "address": {
      "street": "Rex Trail",
      "suite": "Suite 280",
      "city": "Howemouth",
      "zipcode": "58804-1099",
      "geo": {
        "lat": "24.8918",
        "lng": "21.8984"
      }
    },
    "phone": "210.067.6132",
    "website": "elvis.io",
    "company": {
      "name": "Johns Group",
      "catchPhrase": "Configurable multimedia task-force",
      "bs": "generate enterprise e-tailers"
    }
  },
  {
    "id": 8,
    "name": "Nicholas Runolfsdottir V",
    "username": "Maxime_Nienow",
    "email": "Sherwood@rosamond.me",
    "address": {
      "street": "Ellsworth Summit",
      "suite": "Suite 729",
      "city": "Aliyaview",
      "zipcode": "45169",
      "geo": {
        "lat": "-14.3990",
        "lng": "-120.7677"
      }
    },
    "phone": "586.493.6943 x140",
    "website": "jacynthe.com",
    "company": {
      "name": "Abernathy Group",
      "catchPhrase": "Implemented secondary concept",
      "bs": "e-enable extensible e-tailers"
    }
  },
  {
    "id": 9,
    "name": "Glenna Reichert",
    "username": "Delphine",
    "email": "Chaim_McDermott@dana.io",
    "address": {
      "street": "Dayna Park",
      "suite": "Suite 449",
      "city": "Bartholomebury",
      "zipcode": "76495-3109",
      "geo": {
        "lat": "24.6463",
        "lng": "-168.8889"
      }
    },
    "phone": "(775)976-6794 x41206",
    "website": "conrad.com",
    "company": {
      "name": "Yost and Sons",
      "catchPhrase": "Switchable contextually-based project",
      "bs": "aggregate real-time technologies"
    }
  },
  {
    "id": 10,
    "name": "Clementina DuBuque",
    "username": "Moriah.Stanton",
    "email": "Rey.Padberg@karina.biz",
    "address": {
      "street": "Kattie Turnpike",
      "suite": "Suite 198",
      "city": "Lebsackbury",
      "zipcode": "31428-2261",
      "geo": {
        "lat": "-38.2386",
        "lng": "57.2232"
      }
    },
    "phone": "024-648-3804",
    "website": "ambrose.net",
    "company": {
      "name": "Hoeger LLC",
      "catchPhrase": "Centralized empowering task-force",
      "bs": "target end-to-end models"
    }
  }
]
"""




extension URL: @retroactive ZTJSONExportable {
    public func asJSONValue() -> JSON { JSON(self.absoluteString) }
}


/// Double type transformer - converts JSON values to Double
struct TransformDouble: ZTTransform {
    static func transform(_ json: JSON) -> Double? {
        json.doubleValue
    }
}

/// URL type transformer - converts JSON strings to URL
struct TransformHttp: ZTTransform {
    static func transform(_ json: JSON) -> URL? {
        URL(string: json.stringValue)
    }
}

@ZTJSON
struct Company {
    var name: String = ""
    var catchPhrase: String = ""
    @ZTJSONKey("bs")
    var bussness: String = ""
}

extension Company: Swift.CustomStringConvertible, Swift.CustomDebugStringConvertible {
    public var description: String {
"""
{
    name:\"\(name)\", 
    catchPhrase:\"\(catchPhrase)\", 
    bussness:\"\(bussness)\"
    }
"""
    }
    public var debugDescription: String {
        return description
    }
}


@ZTJSON
class BaseAddress {
    var street = ""
    var suite: String = ""
    var city = ""
}


@ZTJSONSubclass
class Address: BaseAddress, @unchecked Sendable {
    var zipcode: String = ""
    
    @ZTJSONTransformer(TransformDouble.self)
    @ZTJSONKey("geo/lat")
    var lat: Double = 0
    
    @ZTJSONTransformer(TransformDouble.self)
    @ZTJSONKey("geo/lng")
    var lng = 0.0
}

extension Address: Swift.CustomStringConvertible, Swift.CustomDebugStringConvertible {
    public var description: String {
"""
{
    street:\"\(street)\", 
    suite:\"\(suite)\", 
    city:\"\(city)\", 
    zipcode:\"\(zipcode)\", 
    lat:\"\(lat)\", 
    lng:\"\(lng)\"
    }
"""
    }
    public var debugDescription: String {
        return description
    }
}


@ZTJSON
struct Geo {
    @ZTJSONTransformer(TransformDouble.self)
    var lat: Double = 0
    
    @ZTJSONTransformer(TransformDouble.self)
    var lng = 0.0
}

extension Geo: Swift.CustomStringConvertible, Swift.CustomDebugStringConvertible {
    public var description: String {
"""
{
    lat:\"\(lat)\", 
    lng:\"\(lng)\"
    }
"""
    }
    public var debugDescription: String {
        return description
    }
}





@ZTJSON
struct User: Sendable {
    @ZTJSONLetDefValue(0)
    let id: Int
    @ZTJSONLetDefValue("")
    let name: String
    @ZTJSONLetDefValue("")
    let username: String
    @ZTJSONLetDefValue("")
    let email: String
    
    var phone = ""
    
    @ZTJSONTransformer(TransformHttp.self)
    var website:URL?
    
    var company: Company = .init()
    
    var address: Address?
}

extension User: Swift.CustomStringConvertible, Swift.CustomDebugStringConvertible {
    public var description: String {
"""
{
    id:\"\(id)\", 
    name:\"\(name)\", 
    username:\"\(username)\", 
    email:\"\(email)\", 
    phone:\"\(phone)\", 
    website:\"\(String(describing: website))\", 
    company:\(company), 
    address:\(String(describing: address))
}
"""
    }
    public var debugDescription: String {
        return description
    }
}






@ZTJSON
class NestAddress {
    @ZTJSONKey("address/street")
    var street = ""
    @ZTJSONKey("address/suite")
    var suite: String = ""
    @ZTJSONKey("address/city")
    var city = ""
    @ZTJSONKey("address/zipcode")
    var zipcode: String = ""
    
    @ZTJSONTransformer(TransformDouble.self)
    @ZTJSONKey("address/geo/lat")
    var lat: Double = 0
    
    @ZTJSONTransformer(TransformDouble.self)
    @ZTJSONKey("address/geo/lng")
    var lng = 0.0
}

extension NestAddress: Swift.CustomStringConvertible, Swift.CustomDebugStringConvertible {
    public var description: String {
"""
{
    street:\"\(street)\", 
    suite:\"\(suite)\", 
    city:\"\(city)\", 
    zipcode:\"\(zipcode)\", 
    lat:\"\(lat)\", 
    lng:\"\(lng)\"
    }
"""
    }
    public var debugDescription: String {
        return description
    }
}
#endif

