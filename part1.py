"""
This script uses Selenium to dynamically web scrape data from Rate My
Professors (RMP) on professor ratings, departments, etc. from five different
Canadian schools, each with some sort of personal meaning to me (some more than
others; see the inline comments if you're actually interested). Each of the
resulting DataFrames is saved to a `.csv` files, later used to construct three
separate hierarchical model with JAGS in R.

Multithreading is used to launch multiple Firefox drivers at once and
concurrently extract data from multiple WebElements within each, mostly just
because I grew impatient with the long runtimes while prototyping (~13 minutes
on my 10-core MacBook M1 Pro, even with multithreading) and decided to keep it
in the final script. It is assumed that the GeckoDriver Unix executable is
placed in the same folder as this script under the name "geckodriver"; if not,
one can easily enough change the `GECKO_PATH` constant accordingly.

Author: Luis M. B. Varona
Title: Assignment 4, Part 1
Institution: Mount Allison University
Course: DATA 4001-A (Advanced Methods in Data Science)
Instructor: Dr. Matthew Betti
Date: April 14, 2025
"""


# %%
import os
import random
import re
import time
import warnings

from concurrent.futures import ThreadPoolExecutor
from typing import Any
from urllib.parse import urljoin

import polars as pl

from selenium.common.exceptions import \
    ElementClickInterceptedException, TimeoutException
from selenium.webdriver import Firefox, FirefoxOptions
from selenium.webdriver.common.by import By
from selenium.webdriver.firefox.service import Service
from selenium.webdriver.remote.webelement import WebElement
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait


# %%
# This is the GeckoDriver path on my computer; update it accordingly for yours
GECKO_PATH: str = os.path.join(os.path.dirname(__file__), 'geckodriver')

SITE: str = 'https://www.ratemyprofessors.com/'
PATH_SEG: str = 'search/professors/'


# %%
SCHOOL_IDS: dict[str, int] = {
    "Acadia University": 1406, # First school I gave a conference talk at
    # My best friend's school; hopefully where I go for my MA Political Science
    "Carleton University": 1420,
    "Memorial University of Newfoundland": 1441, # Also a school I presented at
    "Mount Allison University": 1444, # My current school
    # School with the most gorgeous campus ever (walkways through the trees!)
    "Mount Saint Vincent University": 1445,
}

CSV_DESTS: dict[str, str] = {
    "Acadia University": 'rmp_acadia.csv', # ~500 professors
    "Carleton University": 'rmp_carleton.csv', # ~2900 professors
    "Memorial University of Newfoundland": 'rmp_mun.csv', # ~1900 professors
    "Mount Allison University": 'rmp_mta.csv', # ~350 professors
    "Mount Saint Vincent University": 'rmp_msvu.csv' # ~450 professors
}

SCHEMA: pl.Schema = pl.Schema(
    {
        'Name': pl.Utf8,
        'Rating': pl.Float64,
        'Would Take Again (%)': pl.Int64,
        'Difficulty': pl.Float64,
        'Department': pl.Utf8,
    }
)


# %%
SHOWMORE_SELECTOR: str = '/html/body/div[1]/div/div/div[2]/main/div[1]/div[2]/button'
PROFCARD_SELECTOR: str = '//a[starts-with(@class, "TeacherCard__StyledTeacherCard")]'

NAME_SELECTOR: str = './/*[starts-with(@class, "CardName__StyledCardName")]'
RATING_SELECTOR: str = './/*[starts-with(@class, "CardNumRating__CardNumRatingNumber")]'
DEPARTMENT_SELECTOR: str = './/*[starts-with(@class, "CardSchool__Department")]'
FEEDBACK_SELECTOR: str = './/*[starts-with(@class, "CardFeedback__CardFeedbackNumber")]'


# %%
# Stop the UI from opening, reducing pressure on the GPU
HEADLESS_MODE: bool = True

MIN_WAIT: int = 2
MAX_WAIT: int = 4
MIN_CLICK_PAUSE: float = 0.5
MAX_CLICK_PAUSE: float = 1.5

# Keep clicking "Show More" and processing cards for at most 20 minutes
MAX_SCROLL_TIME: int = 1200


# %%
SCROLL_TIME_WARN: str = "Loading all page content took too long. Consider " \
    f"increasing `MAX_SCROLL_TIME` (currently {MAX_SCROLL_TIME} seconds)."
NO_DATA_WARN: str = "No professor data found this URL"


# %%
# Handle `os.cpu_count()` returning None (e.g., on some virtual machines)
MAX_OUTER_THREADS: int = (os.cpu_count() or 4) // 2
# So the total number of threads is at most 3 times the number of CPUs
MAX_INNER_THREADS: int = 6


# %%
def main():
    handle_gecko_errors()
    start_time = time.time()
    
    # Multithread to scrape multiple universities concurrently
    with ThreadPoolExecutor(MAX_OUTER_THREADS) as executor:
        # Evaluate eagerly to rethrow exceptions raised while multithreading
        list(executor.map(save_school_data, SCHOOL_IDS.keys()))
    
    # Should take between 10 and 20 minutes to run, depending on your hardware
    elapsed_mins = (time.time() - start_time) / 60
    print(f"Program completed in {elapsed_mins:.2f} minutes.")


# %%
def handle_gecko_errors() -> None:
    if not os.path.isfile(GECKO_PATH):
        raise FileNotFoundError(f"GeckoDriver not found at {GECKO_PATH}")
    
    if not os.access(GECKO_PATH, os.X_OK):
        raise PermissionError(f"GeckoDriver not executable at {GECKO_PATH}")


# # %%
def hide_overlay(driver: Firefox, el_class: str) -> None:
    overlay = (WebDriverWait(driver, MAX_WAIT)
               .until(EC.presence_of_element_located((By.CLASS_NAME,
                                                      el_class))))
    # Call JavaScript to hide an overlay blocking the "Show More" button
    driver.execute_script("arguments[0].style.display = 'none';", overlay)


# %%
def click_showmore(driver: Firefox) -> None:
    try:
        time.sleep(random.uniform(MIN_CLICK_PAUSE, MAX_CLICK_PAUSE))
        (WebDriverWait(driver, MAX_WAIT)
         .until(EC.element_to_be_clickable((By.XPATH, SHOWMORE_SELECTOR)))
         .click())
    # The "Show More" button is blocked by another element (e.g., an iframe)
    except ElementClickInterceptedException as e:
        matches = re.findall(r'<[^>]+class="([^"]+)"', str(e))
        el_class = matches[1] # Extract the class of the overlaid element
        hide_overlay(driver, el_class)
        click_showmore(driver) # This recursive call lets us hide all overlays


# %%
def free_card_memory(card: WebElement) -> None:
    # Call JavaScript to free up memory used by the WebElement from the DOM
    card.parent.execute_script("""
        var el = arguments[0];
        el.parentNode.removeChild(el);
    """, card)


# %%
def extract_prof_data(card: WebElement) -> dict[str, Any]:
    try:
        name = card.find_element(By.XPATH, NAME_SELECTOR).text
        rating = float(card.find_element(By.XPATH, RATING_SELECTOR).text)
        department = card.find_element(By.XPATH, DEPARTMENT_SELECTOR).text
        
        # Both "would-take-again" and difficulty have this class attribute
        feedback = card.find_elements(By.XPATH, FEEDBACK_SELECTOR)
        take_again_pct_text = feedback[0].text
        difficulty = float(feedback[1].text)
        
        if take_again_pct_text == 'N/A':
            take_again_pct = None
        else:
            # Get rid of the percent sign before converting to an int
            take_again_pct = int(take_again_pct_text[:-1])
        
        return {
            'Name': name,
            'Rating': rating,
            'Would Take Again (%)': take_again_pct,
            'Difficulty': difficulty,
            'Department': department,
        }
    finally:
        free_card_memory(card)


# %%
def store_and_delete_cards(driver: Firefox) -> list[dict[str, Any]]:
    prof_cards = driver.find_elements(By.XPATH, PROFCARD_SELECTOR)
    
    with ThreadPoolExecutor(MAX_INNER_THREADS) as executor:
        results = executor.map(extract_prof_data, prof_cards)
    
    return list(results)


# %%
def load_and_store_all_content(driver: Firefox) -> list[dict[str, Any]]:
    prof_data = store_and_delete_cards(driver)
    more_content = True
    start_time = time.time()
    
    # Until all content is loaded or `MAX_SCROLL_TIME` seconds have elapsed
    while more_content and time.time() - start_time < MAX_SCROLL_TIME:
        try:
            click_showmore(driver)
            prof_data.extend(store_and_delete_cards(driver))
        except TimeoutException: # There is no longer a "Show More" button
            more_content = False
    
    # Terminated due to excessive runtime, not actually loading all content
    if more_content:
        warnings.warn(SCROLL_TIME_WARN, RuntimeWarning)
    
    return prof_data


# %%
def session_data(source: str, options: FirefoxOptions) -> pl.DataFrame:
    with Firefox(options, Service(GECKO_PATH)) as driver:
        time.sleep(random.uniform(MIN_WAIT, MAX_WAIT)) # Sidestep bot detection
        driver.get(source)
        prof_data = load_and_store_all_content(driver)
    
    if not prof_data:
        warnings.warn(f"{NO_DATA_WARN}: {source}", RuntimeWarning)
    
    return pl.DataFrame(list(prof_data), schema=SCHEMA)


# %%
def save_school_data(school: str) -> None:
    try:
        source = urljoin(SITE, f"{PATH_SEG}{SCHOOL_IDS[school]}")
        # Handle cases where the script is not run from its parent directory
        dest = os.path.join(os.path.dirname(__file__), CSV_DESTS[school])
        options = FirefoxOptions()
        
        if HEADLESS_MODE:
            options.add_argument('--headless')
        
        session_data(source, options).write_csv(dest)
        print(f"Successfully scraped RMP data for {school!r}: {dest!r}\n")
    except Exception as e:
        # Indicate which session resulted in an error
        raise RuntimeError(f"Failed to scrape RMP data for {school!r}") from e


# %%
if __name__ == '__main__':
    main()
