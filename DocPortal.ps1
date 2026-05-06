Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ================= CONFIG =================
$SaveFolder = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "DocPortal"
if (!(Test-Path $SaveFolder)) { New-Item $SaveFolder -ItemType Directory | Out-Null }

$DocumentTypes = @(
    @{ Id="leave"; Name="Leave Application" },
    @{ Id="expense"; Name="Expense Claim" }
)

# ================= FORM =================
$form = New-Object Windows.Forms.Form
$form.Text = "DocPortal"
$form.Size = "1000,650"
$form.StartPosition = "CenterScreen"
$form.BackColor = "#1e1e1e"

# ================= SIDEBAR =================
$sidebar = New-Object Windows.Forms.Panel
$sidebar.Width = 250
$sidebar.Dock = "Left"
$sidebar.BackColor = "#2b2b2b"
$form.Controls.Add($sidebar)

$listBox = New-Object Windows.Forms.ListBox
$listBox.Dock = "Fill"
$listBox.Font = "Segoe UI,11"
$listBox.BackColor = "#2b2b2b"
$listBox.ForeColor = "White"

foreach ($doc in $DocumentTypes) {
    $listBox.Items.Add($doc.Name)
}
$sidebar.Controls.Add($listBox)

# ================= MAIN =================
$main = New-Object Windows.Forms.Panel
$main.Dock = "Fill"
$main.BackColor = "#1e1e1e"
$form.Controls.Add($main)

$title = New-Object Windows.Forms.Label
$title.Font = "Segoe UI,16,Style=Bold"
$title.ForeColor = "White"
$title.Location = "20,20"
$title.AutoSize = $true
$main.Controls.Add($title)

$fieldsPanel = New-Object Windows.Forms.Panel
$fieldsPanel.Location = "20,70"
$fieldsPanel.Size = "700,400"
$fieldsPanel.AutoScroll = $true
$fieldsPanel.BackColor = "#252526"
$main.Controls.Add($fieldsPanel)

$btn = New-Object Windows.Forms.Button
$btn.Text = "Generate"
$btn.Location = "20,500"
$btn.Size = "150,40"
$btn.BackColor = "#007acc"
$btn.ForeColor = "White"
$btn.FlatStyle = "Flat"
$main.Controls.Add($btn)

# ================= STATE =================
$script:controls = @{}
$script:currentDoc = $null

# ================= HELPERS =================
function Clear-Fields {
    $fieldsPanel.Controls.Clear()
    $script:controls = @{}
}

function New-TextBox {
    $tb = New-Object Windows.Forms.TextBox
    $tb.Width = 400
    $tb.BackColor = "White"
    $tb.ForeColor = "Black"
    return $tb
}

function Add-Field($labelText, $y, $control) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $labelText
    $label.ForeColor = "White"
    $label.Location = "10,$y"
    $label.Width = 180

    $control.Location = "200,$y"

    $fieldsPanel.Controls.Add($label)
    $fieldsPanel.Controls.Add($control)

    return $control
}

# ================= LOAD FORM =================
function Load-Form($doc) {
    Clear-Fields
    $script:currentDoc = $doc
    $title.Text = $doc.Name

    $y = 10

    $script:controls["name"] = Add-Field "Full Name" $y (New-TextBox)
    $y += 40

    $script:controls["dept"] = Add-Field "Department" $y (New-TextBox)
    $y += 40

    if ($doc.Id -eq "leave") {
        $cb = New-Object Windows.Forms.ComboBox
        $cb.Items.AddRange(@("Annual","Sick","Personal"))
        $cb.Width = 200
        $cb.BackColor = "White"
        $cb.ForeColor = "Black"

        $script:controls["type"] = Add-Field "Leave Type" $y $cb
        $y += 40

        $script:controls["start"] = Add-Field "Start Date" $y (New-Object Windows.Forms.DateTimePicker)
        $y += 40

        $script:controls["end"] = Add-Field "End Date" $y (New-Object Windows.Forms.DateTimePicker)
    }

    if ($doc.Id -eq "expense") {
        $script:controls["amount"] = Add-Field "Amount" $y (New-TextBox)
        $y += 40

        $txt = New-TextBox
        $txt.Multiline = $true
        $txt.Height = 80

        $script:controls["desc"] = Add-Field "Description" $y $txt
    }

    $fieldsPanel.Refresh()
}

# ================= GENERATE =================
function Generate {
    if (!$script:currentDoc) {
        [Windows.Forms.MessageBox]::Show("Select a document first")
        return
    }

    $name = $script:controls["name"].Text
    $dept = $script:controls["dept"].Text

    if (!$name -or !$dept) {
        [Windows.Forms.MessageBox]::Show("Fill required fields")
        return
    }

    try {
        $word = New-Object -ComObject Word.Application
        $doc = $word.Documents.Add()
        $sel = $word.Selection

        $sel.TypeText("$($script:currentDoc.Name)`r`n`r`n")
        $sel.TypeText("Name: $name`r`nDept: $dept")

        $file = Join-Path $SaveFolder "doc_$(Get-Date -Format HHmmss).docx"
        $doc.SaveAs([ref]$file)

        $doc.Close()
        $word.Quit()

        [Windows.Forms.MessageBox]::Show("Saved to $file")
    }
    catch {
        [Windows.Forms.MessageBox]::Show("Error: Word not installed")
    }
}

# ================= EVENTS =================
$listBox.Add_SelectedIndexChanged({
    if ($listBox.SelectedIndex -ge 0) {
        Load-Form $DocumentTypes[$listBox.SelectedIndex]
    }
})

$btn.Add_Click({ Generate })

$form.ShowDialog()