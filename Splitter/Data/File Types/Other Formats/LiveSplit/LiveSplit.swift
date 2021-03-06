//
//  LiveSplit.swift
//  Splitter
//
//  Created by Michael Berk on 2/5/20.
//  Copyright © 2020 Michael Berk. All rights reserved.
//

import Foundation
import Cocoa
import Files




class LiveSplit: NSObject {
	
	var path: String!
	var data: Data!
	var splits: [splitTableRow] = []
	var icons: [NSImage?] = []
	var gameIcon: NSImage?
	var runTitle: String?
	var category: String?
	var attempts: Int?
	var platform: String?
	var region: String?
	var gameVersion: String?
	
	public var iconArray: [NSImage?] = []
	
	var startDate: String?
	var endDate: String?
	
	var lsPointer: UnsafeMutableRawPointer?
	
	func displayImportDialog() {
		
		let dialog = NSOpenPanel();
		dialog.title                   = "Choose a .lss file";
		dialog.showsResizeIndicator    = true;
		dialog.showsHiddenFiles        = false;
		dialog.canChooseDirectories    = true;
		dialog.canCreateDirectories    = true;
		dialog.allowsMultipleSelection = false;
		dialog.allowedFileTypes        = ["lss"];

		if (dialog.runModal() == NSApplication.ModalResponse.OK) {
			let result = dialog.url // Pathname of the file
			path = result?.path
		}
		
		
	}
	///Parses a `.lss` file
	func parseLivesplit() {
		let lssFile = try? File(path: path)
		let lssData = try? lssFile?.read()
		data = lssData!
		
		let hand = FileHandle(forReadingAtPath: path)
		let handle64 = Int64(hand!.fileDescriptor)
		let cRun = LiveSplitCore.Run.parseFileHandle(handle64, path, true)
		
		if cRun.parsedSuccessfully() {
			let run = cRun.unwrap()
			parseBestSplits(run: run)
			
			runTitle = run.gameName()
			category = run.categoryName()
			let runIconStr = run.gameIcon()
			if let img = parseImageFromLiveSplit(icon: runIconStr) {
				gameIcon = img
			}
			attempts = Int(run.attemptCount())
			platform = run.metadata().platformName()
			region = run.metadata().regionName()
			
			
			
			lsPointer = run.ptr
		}
		
	}
	
	
	private func parseBestSplits(run: LiveSplitCore.Run) {
		let segCount = run.len()
		var i = 0
		var tsArray: [splitTableRow] = []
		while i < segCount {
			
			let segName = run.segment(i).name()
			
			var newTS = TimeSplit(mil: 0)
			if let cTimeDouble = run.segment(i).personalBestSplitTime().realTime()?.totalSeconds() {
				newTS = TimeSplit(seconds: cTimeDouble)
			}
			
			let bestTS = run.segment(i).bestSegmentTime().realTime()?.totalSeconds()
			
			
			//Parse LiveSplit history
			let iter = run.segment(i).segmentHistory().iter()
			var last: Double? = nil
			var secondToLast: Double? = nil
			while (iter.next() != nil) {
				secondToLast = iter.next()?.time().realTime()?.totalSeconds()
				last = iter.next()?.time().realTime()?.totalSeconds()
			}
			
			let imgStr = run.segment(i).icon()
			let img = parseImageFromLiveSplit(icon: imgStr)
			iconArray.append(img)
			
			var newBest = TimeSplit(seconds: bestTS ?? 0)
			if i > 0 {
				newBest = newBest + tsArray[i - 1].bestSplit
			}
			
			let newRow = splitTableRow(splitName: segName, bestSplit: newTS, currentSplit: TimeSplit(), previousSplit: TimeSplit(), previousBest: newBest, splitIcon: nil)
			tsArray.append(newRow)
			i = i + 1
		}
		if tsArray.count > 0 {
			self.splits = tsArray
		}
	}
	
	func parseImageFromLiveSplit(icon: String) -> NSImage? {
		var img:NSImage? = nil
		if let imgURL = URL(string: icon){
			if let imgdata = try? Data(contentsOf: imgURL) {
				img = NSImage(data: imgdata)
			}
		}
		return img
	}
	///Creates a string that to be saved to a `.lss` file
	func liveSplitString() -> String {
		let run = LiveSplitCore.Run()
		let segDel = "If you name a segment this it will be deleted"
		let blankSeg = LiveSplitCore.Segment(segDel)
		var i = 0
		run.pushSegment(blankSeg)
		let lss = LiveSplitCore.RunEditor(run)
		lss?.setGameName(runTitle ?? "")
		lss?.setCategoryName(category ?? " ")
		lss?.setPlatformName(platform ?? "")
		lss?.setRegionName(region ?? "")
		let _ = lss?.parseAndSetAttemptCount("\(attempts ?? 0)")
		
		if var giData = gameIcon?.tiffRepresentation {
			let giLen = giData.count
			let giPtr = giData.withUnsafeMutableBytes( { bytes in
				let UMBP = bytes.baseAddress
				lss?.setGameIcon(UMBP, giLen)
			})
		}
		i = 0
		while i < splits.count {
			lss?.insertSegmentBelow()
			let icon = icons[i]
			
			if var id = icon?.tiffRepresentation {
				let iconlen = id.count
				let iPtr = id.withUnsafeMutableBytes( { bytes in
					let UMBP = bytes.baseAddress
					lss?.activeSetIcon(UMBP, iconlen)
				})
			}
			
			lss?.activeSetName(splits[i].splitName)
			let ts = splits[i].bestSplit.shortTimeString
			lss?.activeParseAndSetSplitTime(ts)
			i = i + 1
		}
		lss?.selectOnly(0)
		lss?.removeSegments()
		run.ptr = lss?.ptr
		///For whatever reason, the expected way to save attempts to lss doesn't work, so I have to brute force it here.
		var returnString = run.saveAsLss()
		returnString = returnString.replacingOccurrences(of: "<AttemptCount>0</AttemptCount>", with: "<AttemptCount>\(attempts ?? 0)</AttemptCount>")
		return returnString
	}
	
	var cdata: Data?

}

extension ViewController {
	func loadLS(ls: LiveSplit) {
		ls.parseLivesplit()
		if ls.splits.count > 0 {
			var i = 0
			
			while i < ls.splits.count {
				currentSplits.append(ls.splits[i].copy() as! splitTableRow)
				i = i + 1
			}
			
		}
		var i = 0
		if ls.iconArray.count > 0 {
			while i < currentSplits.count {
				if ls.iconArray[i] != nil {
					currentSplits[i].splitIcon = ls.iconArray[i]
				}
				i = i + 1
			}
		}
		
		if let gn = ls.runTitle {
			if gn.count > 0 {
				runTitleField.stringValue = gn
			}
		}
		if let sb = ls.category {
			if sb.count > 0 {
				categoryField.stringValue = sb
			}
		}
		
		if let att = ls.attempts {
			attempts = att
		}
		if let reg = ls.region {
			gameRegion = reg
		}
		if let plat = ls.platform {
			platform = plat
		}
		
		
		self.lsPointer = ls.lsPointer
		self.gameIcon = ls.gameIcon
		splitsTableView.reloadData()
	}
}


extension String {
    subscript (bounds: CountableClosedRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start...end])
    }

    subscript (bounds: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start..<end])
    }
}


//yourString.toImage() // it will convert String  to UIImage

extension String {
    func toImage() -> NSImage? {
        if let data = Data(base64Encoded: self, options: .ignoreUnknownCharacters){
            return NSImage(data: data)
        }
        return nil
    }
}
