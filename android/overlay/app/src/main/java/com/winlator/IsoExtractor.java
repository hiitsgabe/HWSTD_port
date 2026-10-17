package com.winlator;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.FileChannel;
import java.util.Locale;

/**
 * Minimal ISO 9660 reader: copies one directory tree out of a CD image.
 * Plain Java (no Android classes) so it can be checked on a desktop JVM:
 *   javac IsoExtractor.java && java -cp . com.winlator.IsoExtractor game.iso SETUP/HOT98 out/
 */
// Primary volume descriptor only (no Joliet/Rock Ridge); the Stunt Track Driver disc needs nothing more.
public final class IsoExtractor {
    private static final int SECTOR = 2048;
    private final FileChannel channel;

    public IsoExtractor(FileChannel channel) {
        this.channel = channel;
    }

    private ByteBuffer read(long lba, int size) throws IOException {
        ByteBuffer buffer = ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN);
        long position = lba * SECTOR;
        while (buffer.hasRemaining()) {
            if (channel.read(buffer, position + buffer.position()) < 0) throw new IOException("Unexpected end of ISO");
        }
        buffer.flip();
        return buffer;
    }

    /** Returns {lba, size} of the directory at path (e.g. "SETUP/HOT98"), or null if missing. */
    private int[] findDirectory(String path) throws IOException {
        ByteBuffer pvd = read(16, SECTOR);
        if (pvd.get(0) != 1 || !"CD001".equals(new String(pvd.array(), 1, 5, "US-ASCII"))) throw new IOException("Not an ISO 9660 image");
        int[] dir = {pvd.getInt(156 + 2), pvd.getInt(156 + 10)};
        for (String part : path.split("/")) {
            if (part.isEmpty()) continue;
            int[] next = null;
            for (Entry entry : list(dir)) {
                if (entry.isDirectory && entry.name.equalsIgnoreCase(part)) next = new int[]{entry.lba, entry.size};
            }
            if (next == null) return null;
            dir = next;
        }
        return dir;
    }

    private static final class Entry {
        String name;
        int lba, size;
        boolean isDirectory;
    }

    private java.util.List<Entry> list(int[] dir) throws IOException {
        java.util.ArrayList<Entry> entries = new java.util.ArrayList<>();
        ByteBuffer data = read(dir[0], dir[1]);
        int i = 0;
        while (i < dir[1]) {
            int length = data.get(i) & 0xff;
            if (length == 0) { // records never cross sectors; skip padding
                i = (i / SECTOR + 1) * SECTOR;
                continue;
            }
            int nameLength = data.get(i + 32) & 0xff;
            byte first = data.get(i + 33);
            if (!(nameLength == 1 && (first == 0 || first == 1))) {
                Entry entry = new Entry();
                entry.lba = data.getInt(i + 2);
                entry.size = data.getInt(i + 10);
                entry.isDirectory = (data.get(i + 25) & 2) != 0;
                String name = new String(data.array(), i + 33, nameLength, "ISO-8859-1");
                int version = name.indexOf(';');
                if (version != -1) name = name.substring(0, version);
                if (name.endsWith(".")) name = name.substring(0, name.length() - 1);
                entry.name = name.toLowerCase(Locale.ENGLISH);
                entries.add(entry);
            }
            i += length;
        }
        return entries;
    }

    public interface Progress {
        void onProgress(long bytesWritten);
    }

    /** Copies the tree at isoPath into destDir. Returns false if isoPath does not exist in the image. */
    public boolean extract(String isoPath, File destDir, Progress progress) throws IOException {
        int[] dir = findDirectory(isoPath);
        if (dir == null) return false;
        extractTree(dir, destDir, progress, new long[1]);
        return true;
    }

    private void extractTree(int[] dir, File destDir, Progress progress, long[] total) throws IOException {
        if (!destDir.isDirectory() && !destDir.mkdirs()) throw new IOException("Cannot create " + destDir);
        for (Entry entry : list(dir)) {
            File dest = new File(destDir, entry.name);
            if (entry.isDirectory) {
                extractTree(new int[]{entry.lba, entry.size}, dest, progress, total);
                continue;
            }
            try (FileChannel out = new FileOutputStream(dest).getChannel()) {
                long position = (long)entry.lba * SECTOR, end = position + entry.size;
                while (position < end) position += channel.transferTo(position, end - position, out);
            }
            total[0] += entry.size;
            if (progress != null) progress.onProgress(total[0]);
        }
    }

    public static void main(String[] args) throws IOException {
        try (RandomAccessFile file = new RandomAccessFile(args[0], "r")) {
            boolean found = new IsoExtractor(file.getChannel()).extract(args[1], new File(args[2]), null);
            if (!found) throw new AssertionError(args[1] + " not found in " + args[0]);
            System.out.println("ok");
        }
    }
}
