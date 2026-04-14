*** Lisätään kirjastoja ***

*** Settings ***
Library    DatabaseLibrary
Library    Collections
Library    OperatingSystem
Library    String
Library    DateTime
Library    validate.py
Library    Process

*** Variables ***
${PATH}    C:\\projects\\Invoice-Automation-Project\\Laskutusautomaatio\\rpa_robotframework\\ 

# database variables
${dbname}    invoice_rpa
${dbuser}    robotuser
${dbpass}    password
${dbhost}    localhost
${dbport}    3306

*** Keywords ***
Make Connection
    [Arguments]    ${dbtoconnect}
    Connect To Database    pymysql    ${dbtoconnect}    ${dbuser}    ${dbpass}    ${dbhost}    ${dbport}

*** Keywords ***
Add Invoice Header To DB
    [Arguments]    ${items}
    Make Connection    ${dbname}
    
    # Convert dates to correct format
    ${invoiceDate}=    Convert Date    ${items}[3]    date_format=%d.%m.%Y    result_format=%Y-%m-%d
    ${dueDate}=    Convert Date    ${items}[4]    date_format=%d.%m.%Y    result_format=%Y-%m-%d

    ${insertStmt}=    Set Variable    INSERT INTO invoiceheader (invoicenumber, companyname, companycode, referencenumber, invoicedate, duedate, bankaccountnumber, amountexclvat, vat, totalamount, invoicestatus_id, comments) VALUES ('${items[0]}', '${items[1]}', '${items[5]}', '${items[2]}', '${invoiceDate}', '${dueDate}','${items[6]}', '${items[7]}', '${items[8]}', '${items[9]}', -1, 'Prosessing');
    Log    ${insertStmt}
    Execute Sql String    ${insertStmt}

    Disconnect From Database

*** Keywords ***
Add InvoiceRow To DB
    [Arguments]    ${items}
    Make Connection    ${dbname}

    ${insertStmt}=    Set Variable    INSERT INTO InvoiceRow (invoicenumber, rownumber, description, quantity, unit, unitprice, vatpercent, vat, total) VALUES ('${items[7]}', '${items[8]}', '${items[0]}', '${items[1]}', '${items[2]}', '${items[3]}', '${items[4]}', '${items[5]}', ${items[6]});
    Log    ${insertStmt}
    Execute Sql String    ${insertStmt}

    Disconnect From Database

*** Keywords ***
Check IBAN
    [Arguments]    ${iban}
    ${status}=    Set Variable    ${False}

    ${iban}=    Remove String    ${SPACE}

    ${length}=    Get Length    ${iban}

    IF    ${length} == 18
        ${status}=    Set Variable    ${True}
    END

    RETURN    ${status}

*** Keywords ***
Check Amounts From Invoice
    [Arguments]    ${totalSumFromHeader}    ${totalSumFromRows}
    ${status}=    Set Variable    ${False}

    ${totalSumFromHeader}=    Convert To Number    ${totalSumFromHeader}
    ${totalSumFromRows}=    Convert To Number    ${totalSumFromRows}
    ${diff}=    Convert To Number    0.01

    ${status}=    Is Equal    ${totalSumFromHeader}    ${totalSumFromRows}    ${diff}


    RETURN    ${status}

*** Tasks ***
Read CSV file to list and add data to database
    Make Connection    ${dbname}

    ${outputHeader}=    Get File    ${PATH}InvoiceHeaderData.csv
    ${outputRows}=    Get File    ${PATH}InvoiceRowData.csv
    Log    ${outputHeader}
    Log    ${outputRows}

    # each row read as an element to list
    @{headers}=    Split String    ${outputHeader}    \n
    @{rows}=    Split String    ${outputRows}    \n

    # remove last row and first row from lists (last=empty, first=header)
    ${length}=    Get Length    ${headers}
    ${length}=    Evaluate    ${length} - 1
    ${index}=    Convert To Integer    0

    Remove From List    ${headers}    ${length}
    Remove From List    ${headers}    ${index}

    # next for rows
    ${length}=    Get Length    ${rows}
    ${length}=    Evaluate    ${length} - 1

    Remove From List    ${rows}    ${length}
    Remove From List    ${rows}    ${index}

    Log    ${headers}
    Log    ${rows}
    
    #Add invoice headers
    FOR    ${headerElement}    IN    @{headers}
        Log    ${headerElement}
        @{headerItems}=    Split String    ${headerElement}    ;

        Add Invoice Header To DB    ${headerItems}
        
    END
    
    # Add invoice rows
    FOR    ${rowElement}    IN    @{rows}
        Log    ${rowElement}
        @{rowItems}=    Split String    ${rowElement}    ;

        Add InvoiceRow To DB    ${rowItems}
        
    END

*** Tasks ***
validate and update validation info to DB
    #Find all invoices with status -1 processing
    #validations:
    #     referencenumber
    #iban
    #invoice row amoint vs header amount
    Make Connection    ${dbname}

    #Find invoices
    ${invoices}=    Query    select invoicenumber, referencenumber, bankaccountnumber, totalamount from invoiceheader where invoicestatus_id = -1;

    FOR    ${element}    IN    @{invoices}
        Log    ${element}
        ${invoiceStatus}=    Set Variable    0
        ${invoiceComment}=    Set Variable    All Ok

        #Validate referencenumber
        ${refStatus}=    Is Reference Number Correct    ${element}[1]

        #Validate IBAN
        ${ibanStatus}=    Check IBAN    ${element}[1]

        #invoice row amount vs header amount
        @{params}=    Create List    ${element}[0]
        ${rowAmount}=    Query    select sum(total) from invoicerow where invoicenumber = %s;    parameters=${params}
        
        ${sumStatus}=    Check Amounts From Invoice    ${element}[3]    ${rowAmount}[0][0]

        #Update status to db
        @{params}=    Create List    ${invoiceStatus}    ${invoiceComment}    ${element}[0]
        ${updateStmt}=    Set Variable    update invoiceheader set invoicestatus_id = %s, comments = %s where invoicenumber = %s;
        Execute Sql String    ${updateStmt}    parameters=${params}
    END

    Disconnect From Database
