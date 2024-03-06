from memory.memory import memcpy
from MojoFastTrim.helpers import get_next_line_index, slice_tensor, cpy_tensor
from MojoFastTrim.CONSTS import simd_width, I8
from math.math import min
from pathlib import Path
import time

alias KB = 1024
alias MB = 1024 * KB
alias GB = 1024 * MB
alias DEFAULT_CAPACITY = 64 * KB
alias MAX_CAPACITY = 1 * GB


# Implement functionality from: Buffer-Reudx rust cate allowing for BufferedReader that supports partial reading and filling ,
# https://github.com/dignifiedquire/buffer-redux
# Minimial Implementation that support only line iterations
# Caveat: Currently does not support buffer-resize at runtime.


trait reader:
    fn read_bytes(inout self, amt: Int) raises -> Tensor[I8]:
        ...

    fn __moveinit__(inout self, owned other: Self):
        ...


struct FileReader(reader):
    var file_handle: FileHandle

    fn __init__(inout self, path: Path) raises:
        self.file_handle = open(path, "r")

    fn read_bytes(inout self, amt: Int) raises -> Tensor[I8]:
        return self.file_handle.read_bytes(amt)

    fn __moveinit__(inout self, owned other: Self):
        self.file_handle = other.file_handle ^


struct TensorReader(reader):
    var pos: Int
    var source: Tensor[I8]

    fn __init__(inout self, source: Tensor[I8]):
        self.source = source
        self.pos = 0

    fn read_bytes(inout self, amt: Int) raises -> Tensor[I8]:
        var ele = min(amt, self.source.num_elements() - self.pos)

        if ele == 0:
            return Tensor[I8](0)

        var out = Tensor[I8](ele)
        cpy_tensor[I8](out, self.source, out.num_elements(), 0, self.pos)
        self.pos += out.num_elements()
        return out

    fn __moveinit__(inout self, owned other: Self):
        self.source = other.source ^
        self.pos = other.pos


struct IOStream[T: reader, check_ascii: Bool = False](Sized, Stringable):
    """A poor man's BufferedReader that takes as input a FileHandle or an in-memory Tensor and provides a buffered reader on-top with default capactiy.
    """

    var source: T
    var buf: Tensor[I8]
    var head: Int
    var end: Int
    var consumed: Int
    var EOF: Bool

    fn __init__(inout self, source: Path, capacity: Int = DEFAULT_CAPACITY) raises:
        if source.exists():
            self.source = FileReader(source)
        else:
            raise Error("Provided file not found for read")
        self.buf = Tensor[I8](capacity)
        self.head = 0
        self.end = 0
        self.consumed = 0
        self.EOF = False
        _ = self.fill_buffer()

    fn __init__(
        inout self, source: Tensor[I8], capacity: Int = DEFAULT_CAPACITY
    ) raises:
        self.source = TensorReader(source)
        self.buf = Tensor[I8](capacity)
        self.head = 0
        self.end = 0
        self.consumed = 0
        self.EOF = False
        _ = self.fill_buffer()

    @always_inline
    fn check_buf_state(inout self) -> Bool:
        if self.head >= self.end:
            self.head = 0
            self.end = 0
            return True
        else:
            return False

    @always_inline
    fn left_shift(inout self):
        """Checks if there is remaining elements in the buffer and copys them to the beginning of buffer to allow for partial reading of new data.
        """
        if self.head == 0:
            return

        var no_items = self.len()
        cpy_tensor[I8](self.buf, self.buf, no_items, 0, self.head)
        self.head = 0
        self.end = no_items

    @always_inline
    fn fill_buffer(inout self) raises -> Int:
        """Returns the number of bytes read into the buffer."""

        self.left_shift()
        var nels = self.uninatialized_space()
        var in_buf = self.source.read_bytes(nels)

        if in_buf.num_elements() == 0:
            raise Error("EOF")

        if in_buf.num_elements() < nels:
            self._resize_buf(in_buf.num_elements() - nels, MAX_CAPACITY)

        self._store[self.check_ascii](in_buf, in_buf.num_elements())
        self.consumed += nels
        return in_buf.num_elements()

    fn read_next_line(inout self) raises -> Tensor[I8]:
        if self.check_buf_state():
            _ = self.fill_buffer()

        var line_start = self.head
        var line_end = get_next_line_index(self.buf, line_start)

        if line_end == -1:
            if self.head == 0:
                self._resize_buf(self.capacity(), MAX_CAPACITY)
                _ = self.fill_buffer()
                return self.read_next_line()

            _ = self.fill_buffer()
            return self.read_next_line()

        self.head = line_end + 1
        return slice_tensor[I8](self.buf, line_start, line_end)

    # Inlining, elimination of recursion increases performance 10%.
    fn next_line_coord(inout self) raises -> Slice:
        if self.check_buf_state():
            _ = self.fill_buffer()

        var line_start = self.head
        var line_end = get_next_line_index(self.buf, self.head)

        if line_end == -1:
            if self.head == 0:
                self._resize_buf(self.capacity(), MAX_CAPACITY)
                _ = self.fill_buffer()
                return self.next_line_coord()

            _ = self.fill_buffer()
            return self.next_line_coord()

        self.head = line_end + 1
        return slice(line_start + self.consumed, line_end + self.consumed)

    @always_inline
    fn _store[
        check_ascii: Bool = False
    ](inout self, in_tensor: Tensor[I8], amt: Int) raises:
        @parameter
        if check_ascii:
            self._check_ascii(in_tensor)

        cpy_tensor[I8](self.buf, in_tensor, amt, self.end, 0)
        self.end += amt

    @always_inline
    @staticmethod
    fn _check_ascii(in_tensor: Tensor[I8]) raises:
        var aligned = math.align_down(in_tensor.num_elements(), simd_width)
        for i in range(0, aligned, simd_width):
            var vec = in_tensor.simd_load[simd_width](i)
            var mask = vec & 0x80
            var mask2 = mask.reduce_max()
            var mask3 = mask.reduce_min()
            if mask2 != 0 or mask3 != 0:
                raise Error("Non ASCII letters found")
        for i in range(aligned, in_tensor.num_elements()):
            if in_tensor[i] & 0x80 != 0:
                raise Error("Non ASCII letters found")

    # There is no way in Mojo to do that right now
    fn _resize_buf(inout self, amt: Int, max_capacity: Int) raises:
        if self.capacity() == max_capacity:
            raise Error("Buffer is at max capacity")

        var nels: Int
        if self.capacity() + amt > max_capacity:
            nels = max_capacity
        else:
            nels = self.capacity() + amt
        var x = Tensor[I8](nels)
        var nels_to_copy = min(self.capacity(), self.capacity() + amt)
        cpy_tensor[I8](x, self.buf, nels_to_copy, 0, 0)
        self.buf = x

    ########################## Helpers functions, have no side effects #######################

    @always_inline
    fn map_pos_2_buf(self, file_pos: Int) -> Int:
        return file_pos - self.consumed

    @always_inline
    fn len(self) -> Int:
        return self.end - self.head

    @always_inline
    fn capacity(self) -> Int:
        return self.buf.num_elements()

    @always_inline
    fn uninatialized_space(self) -> Int:
        return self.capacity() - self.end

    @always_inline
    fn usable_space(self) -> Int:
        return self.uninatialized_space() + self.head

    @always_inline
    fn __len__(self) -> Int:
        return self.end - self.head

    @always_inline
    fn __str__(self) -> String:
        var out = Tensor[I8](self.len())
        cpy_tensor[I8](out, self.buf, self.len(), 0, self.head)
        return String(out._steal_ptr(), self.len())

    fn __getitem__(self, index: Int) -> Scalar[I8]:
        return self.buf[index]

    fn __getitem__(self, slice: Slice) -> Tensor[I8]:
        var out = Tensor[I8](slice.end - slice.start)
        cpy_tensor[I8](out, self.buf, slice.end - slice.start, 0, slice.start)
        return out


fn main() raises:
    var p = "/home/mohamed/Documents/Projects/Fastq_Parser/data/M_abscessus_HiSeq.fq"
    # var h = open(p, "r").read_bytes()
    var buf = IOStream[FileReader, check_ascii=False](p, capacity=64 * 1024)
    var line_no = 0
    while True:
        try:
            var line = buf.next_line_coord()
            line_no += 1
        except Error:
            print(Error)
            print(line_no)
            break
