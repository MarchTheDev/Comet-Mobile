//
//  FirstRun.swift
//  Comet for iOS
//
//  Comet works on a folder you choose. On a desktop that is any directory; on
//  iOS the one place the app can always reach is its own Documents directory,
//  and because the build declares file sharing, that folder is visible in
//  Files under "On My iPhone → Comet". Seeding it once gives the workspace
//  picker somewhere obvious to point at.
//

import Foundation

enum FirstRun {
    static func prepare() {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("Comet", isDirectory: true)
        guard !fileManager.fileExists(atPath: folder.path) else { return }
        guard (try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return }

        let welcome = """
        # Welcome to Comet

        This folder is a Comet workspace. Everything in it is ordinary files on
        this device: open them in any other app, sync them with iCloud Drive by
        keeping the workspace there, or copy the folder somewhere else. Comet
        has no account and no server.

        ## Getting started

        - Press **Open workspace** and choose this folder
          (**On My iPhone → Comet**) to work in it.
        - Or choose any other folder on the device or in iCloud Drive. Comet
          remembers it, and asks iOS to keep access to it next time.
        - Create notes, to-do boards and whiteboards from the **+** button.
          Drop files in with **Quick capture**, or press the folder button.

        ## What works here

        Notes and Markdown editing, to-do boards, whiteboards, tags, pins,
        search, the Tree and Brain views, PDFs, EPUB books, images, audio and
        video, the calendar, and the encrypted Passwords vault all run on this
        device exactly as they do on the desktop.

        ## What a phone and a tablet do not have

        - **Google Calendar and Drive** are not connected in this build, so
          those settings report that they are unavailable. The local calendar
          and the workspace are unaffected.
        - **The tray, launching at login, and closing to the tray** are desktop
          ideas; their switches are inert here.
        - **Updates** are installed by sideloading a newer build, not from
          inside the app.

        ## Where settings live

        Tags, pins, favorites, sidebar order, workspace names and icons,
        keyboard shortcuts, calendars and preferences are kept in Comet's
        storage on this device, not in this folder, so they travel with the app
        rather than with the files. Back up the files in this folder yourself;
        they are yours.

        — Comet
        """
        let note = folder.appendingPathComponent("Welcome.md")
        try? Data(welcome.utf8).write(to: note, options: .atomic)
    }
}
